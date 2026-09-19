import Foundation
import SQLCore

public actor MySQLConnection: DatabaseConnection {
    public let profile: ConnectionProfile

    private let transport: any MySQLTransporting
    private var handshake: MySQLHandshake?
    private var capabilities: MySQLCapabilities = []
    private var packetSequence: UInt8 = 0
    private var connected = false
    private var tlsActive = false
    private var password: String?

    private var queryOperationBusy = false
    private var queryOperationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(profile: ConnectionProfile) {
        self.profile = profile
        self.transport = MySQLTransport()
    }

    init(profile: ConnectionProfile, transport: any MySQLTransporting) {
        self.profile = profile
        self.transport = transport
    }

    public func isConnected() async -> Bool { connected }

    public func connect(password: String?) async throws {
        guard !connected else { return }
        guard !profile.host.isEmpty, profile.port > 0 else {
            throw SQLDriverError.connectionFailed(message: "MySQL host and port are required")
        }

        do {
            try await transport.connect(host: profile.host, port: profile.port)
            packetSequence = 0
            let greeting = try await readPacket()
            let parsedHandshake = try MySQLHandshake.parse(greeting.payload)
            handshake = parsedHandshake
            capabilities = try MySQLAuth.buildCapabilities(
                handshake: parsedHandshake,
                database: profile.database,
                tlsMode: profile.tlsMode
            )

            if capabilities.contains(.ssl) {
                try await sendPacket(MySQLAuth.sslRequest(capabilities: capabilities), sequence: 1)
                packetSequence = 2
                try await transport.startTLS(
                    serverName: profile.tlsServerName ?? profile.host,
                    verifyCertificate: profile.tlsMode.verifiesCertificate
                )
                tlsActive = true
            } else {
                tlsActive = false
            }

            let plugin = parsedHandshake.authPlugin.isEmpty ? "mysql_native_password" : parsedHandshake.authPlugin
            let token = try MySQLAuth.authToken(
                password: password ?? "",
                plugin: plugin,
                scramble: parsedHandshake.scramble
            )
            let response = MySQLAuth.handshakeResponse(
                username: profile.username,
                database: profile.database,
                passwordToken: token,
                plugin: plugin,
                capabilities: capabilities
            )
            try await sendPacket(response, sequence: packetSequence)
            packetSequence &+= 1
            try await finishAuthentication(password: password ?? "", initialPlugin: plugin, scramble: parsedHandshake.scramble)
            self.password = password
            connected = true
            if profile.readOnly {
                do {
                    _ = try await execute("SET SESSION TRANSACTION READ ONLY")
                } catch let error as MySQLWireError {
                    guard case .serverError = error else { throw error }
                }
            }
        } catch {
            await hardClose()
            throw error
        }
    }

    public func disconnect() async throws {
        if connected {
            packetSequence = 0
            try? await sendPacket(Data([MySQLPrepared.comQuit]), sequence: 0)
        }
        await hardClose()
        resetQueryOperationGate()
    }

    public func cancelInFlight() async {
        guard connected, let connectionID = handshake?.connectionID else {
            await hardClose()
            return
        }
        var cancelProfile = profile
        cancelProfile.readOnly = false
        let side = MySQLConnection(profile: cancelProfile)
        do {
            try await side.connect(password: password)
            do {
                _ = try await side.execute(MySQLCancel.killQuerySQL(connectionID: connectionID))
            } catch let error as MySQLWireError where MySQLCancel.isBenignKillError(error) {
            }
            try? await side.disconnect()
        } catch {
        }
    }

    public func execute(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        try requireConnected()
        try enforceReadOnly(sql)
        await beginQueryOperation()
        defer { endQueryOperation() }
        if parameters.isEmpty {
            try await sendCommand(MySQLPrepared.comQuery, payload: Data(sql.utf8))
            let start = try await readResultStart(binaryRows: false)
            if let affected = start.affectedRows {
                try await drainMoreResults(after: start.statusFlags, binaryRows: false)
                return QueryResult(affectedRowCount: affected)
            }
            var rows: [SQLRow] = []
            var statusFlags = start.statusFlags
            while let row = try await readNextRow(
                columns: start.columns,
                binary: false,
                statusFlags: &statusFlags
            ) {
                rows.append(row)
            }
            try await drainMoreResults(after: statusFlags, binaryRows: false)
            return QueryResult(columns: start.columns, rows: rows)
        }

        return try await executePrepared(sql, parameters: parameters)
    }

    public func stream(_ sql: String) async throws -> StreamedQuery {
        try requireConnected()
        try enforceReadOnly(sql)
        await beginQueryOperation()
        var handedOff = false
        defer {
            if !handedOff {
                endQueryOperation()
            }
        }
        try await sendCommand(MySQLPrepared.comQuery, payload: Data(sql.utf8))
        let start = try await readResultStart(binaryRows: false)
        guard let columns = start.columns else {
            try await drainMoreResults(after: start.statusFlags, binaryRows: false)
            return StreamedQuery(columns: [], rows: RowStream { $0.finish() })
        }
        handedOff = true
        return StreamedQuery(
            columns: columns,
            rows: makeRowStream(columns: columns, initialStatus: start.statusFlags)
        )
    }

    public func serverVersion() async throws -> String? {
        try requireConnected()
        return handshake?.serverVersion
    }

    private func makeRowStream(columns: [SQLColumn], initialStatus: UInt16) -> RowStream {
        RowStream { continuation in
            Task {
                do {
                    var statusFlags = initialStatus
                    while let row = try await self.readNextRow(
                        columns: columns,
                        binary: false,
                        statusFlags: &statusFlags
                    ) {
                        continuation.yield(row)
                    }
                    try await self.drainMoreResults(after: statusFlags, binaryRows: false)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                self.endQueryOperation()
            }
        }
    }

    private func beginQueryOperation() async {
        while queryOperationBusy {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                queryOperationWaiters.append(cont)
            }
        }
        queryOperationBusy = true
    }

    private func endQueryOperation() {
        queryOperationBusy = false
        guard !queryOperationWaiters.isEmpty else { return }
        let next = queryOperationWaiters.removeFirst()
        next.resume()
    }

    private func resetQueryOperationGate() {
        queryOperationBusy = false
        let waiters = queryOperationWaiters
        queryOperationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func hardClose() async {
        await transport.close()
        connected = false
        handshake = nil
        password = nil
        tlsActive = false
    }

    // MARK: - Authentication

    private func finishAuthentication(password: String, initialPlugin: String, scramble: Data) async throws {
        var plugin = initialPlugin
        var currentScramble = scramble
        while true {
            let packet = try await readPacket()
            guard let first = packet.payload.first else { throw MySQLWireError.invalidPacket }
            switch first {
            case 0x00:
                _ = try MySQLAuth.parseOK(packet.payload)
                return
            case 0xff:
                throw try MySQLAuth.parseError(packet.payload)
            case 0xfe where packet.payload.count > 1:
                var reader = MySQLByteReader(data: packet.payload, offset: 1)
                plugin = try reader.readCString()
                currentScramble = try reader.readBytes(packet.payload.count - reader.offset)
                let token = try MySQLAuth.authToken(password: password, plugin: plugin, scramble: currentScramble)
                try await sendPacket(token, sequence: packetSequence)
                packetSequence &+= 1
            case 0x01:
                guard packet.payload.count >= 2 else { throw MySQLWireError.invalidPacket }
                let status = packet.payload[packet.payload.startIndex + 1]
                if status == 0x03 {
                    continue
                }
                if status == 0x04 {
                    guard tlsActive else { throw MySQLWireError.tlsRequired }
                    var response = Data(password.utf8)
                    response.append(0)
                    try await sendPacket(response, sequence: packetSequence)
                    packetSequence &+= 1
                    continue
                }
                throw MySQLWireError.authenticationFailed("Unknown authentication status \(status)")
            default:
                throw MySQLWireError.authenticationFailed("Unexpected authentication packet 0x\(String(first, radix: 16))")
            }
        }
    }

    // MARK: - Result Sets

    private struct ResultStart {
        var columns: [SQLColumn]?
        var affectedRows: Int?
        var binaryRows: Bool
        var statusFlags: UInt16
    }

    private var negotiatedDeprecateEOF: Bool {
        capabilities.contains(.deprecateEOF)
    }

    private func readResultStart(binaryRows: Bool) async throws -> ResultStart {
        let packet = try await readPacket()
        guard let first = packet.payload.first else { throw MySQLWireError.invalidPacket }
        if first == 0xff {
            throw try MySQLAuth.parseError(packet.payload)
        }
        if first == 0x00 {
            let ok = try MySQLAuth.parseOK(packet.payload)
            guard ok.affectedRows <= UInt64(Int.max) else { throw MySQLWireError.invalidPacket }
            return ResultStart(
                columns: nil,
                affectedRows: Int(ok.affectedRows),
                binaryRows: binaryRows,
                statusFlags: ok.status
            )
        }

        var reader = MySQLByteReader(data: packet.payload)
        guard let count = try reader.readLengthEncodedInteger(), count <= UInt64(Self.maximumColumnCount) else {
            throw MySQLWireError.invalidPacket
        }
        var definitions: [MySQLColumnDefinition] = []
        definitions.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            let definitionPacket = try await readPacket()
            definitions.append(try MySQLColumnDefinition.parse(definitionPacket.payload))
        }
        var statusFlags: UInt16 = 0
        if !negotiatedDeprecateEOF {
            let terminator = try await readPacket()
            guard let flags = MySQLRowCodec.rowTerminatorStatus(terminator.payload, deprecateEOF: false) else {
                throw MySQLWireError.invalidPacket
            }
            statusFlags = flags
        }
        let columns = MySQLRowCodec.columns(from: definitions)
        return ResultStart(
            columns: columns,
            affectedRows: nil,
            binaryRows: binaryRows,
            statusFlags: statusFlags
        )
    }

    private func readNextRow(
        columns: [SQLColumn]?,
        binary: Bool,
        statusFlags: inout UInt16
    ) async throws -> SQLRow? {
        guard let columns else { return nil }
        let deprecateEOF = negotiatedDeprecateEOF
        let packet = try await readPacket()
        guard let first = packet.payload.first else { throw MySQLWireError.invalidPacket }
        if first == 0xff { throw try MySQLAuth.parseError(packet.payload) }
        if let flags = MySQLRowCodec.rowTerminatorStatus(packet.payload, deprecateEOF: deprecateEOF) {
            statusFlags = flags
            return nil
        }
        return try binary
            ? MySQLRowCodec.parseBinaryRow(packet.payload, columns: columns)
            : MySQLRowCodec.parseTextRow(packet.payload, columns: columns)
    }

    private func drainMoreResults(after initialStatus: UInt16, binaryRows: Bool) async throws {
        var statusFlags = initialStatus
        var resultCount = 0
        while statusFlags & MySQLServerStatus.moreResults != 0 {
            resultCount += 1
            guard resultCount <= Self.maximumResultSets else {
                throw MySQLWireError.protocolError("Too many MySQL result sets")
            }
            let next = try await readResultStart(binaryRows: binaryRows)
            guard let columns = next.columns else {
                statusFlags = next.statusFlags
                continue
            }
            var finalStatus = next.statusFlags
            while try await readNextRow(
                columns: columns,
                binary: binaryRows,
                statusFlags: &finalStatus
            ) != nil {}
            statusFlags = finalStatus
        }
    }

    // MARK: - Prepared Statements

    private func executePrepared(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        try await sendCommand(MySQLPrepared.comStmtPrepare, payload: Data(sql.utf8))
        let prepared = try await readPacket()
        guard prepared.payload.first == 0x00 else { throw try MySQLAuth.parseError(prepared.payload) }
        var reader = MySQLByteReader(data: prepared.payload, offset: 1)
        let statementID = try reader.readUInt32()
        let columnCount = Int(try reader.readUInt16())
        let parameterCount = Int(try reader.readUInt16())
        let deprecateEOF = negotiatedDeprecateEOF
        if parameterCount > 0 {
            for _ in 0..<parameterCount { _ = try await readPacket() }
            if !deprecateEOF { _ = try await readPacket() }
        }
        if columnCount > 0 {
            for _ in 0..<columnCount { _ = try await readPacket() }
            if !deprecateEOF { _ = try await readPacket() }
        }

        try await sendCommand(
            MySQLPrepared.comStmtExecute,
            payload: MySQLPrepared.buildExecutePayload(statementID: statementID, parameters: parameters)
        )
        let start = try await readResultStart(binaryRows: true)
        if let affected = start.affectedRows {
            try await drainMoreResults(after: start.statusFlags, binaryRows: true)
            try? await closePrepared(statementID)
            return QueryResult(affectedRowCount: affected)
        }
        var rows: [SQLRow] = []
        var statusFlags = start.statusFlags
        while let row = try await readNextRow(
            columns: start.columns,
            binary: true,
            statusFlags: &statusFlags
        ) {
            rows.append(row)
        }
        try await drainMoreResults(after: statusFlags, binaryRows: true)
        try? await closePrepared(statementID)
        return QueryResult(columns: start.columns, rows: rows)
    }

    private func closePrepared(_ statementID: UInt32) async throws {
        try await sendCommand(MySQLPrepared.comStmtClose, payload: MySQLWire.uint32(statementID))
    }

    // MARK: - Packet Helpers

    private func requireConnected() throws {
        guard connected else { throw SQLDriverError.connectionFailed(message: "Not connected") }
    }

    private func sendCommand(_ command: UInt8, payload: Data) async throws {
        packetSequence = 0
        var body = Data([command])
        body.append(payload)
        try await sendPacket(body, sequence: 0)
        packetSequence = 1
    }

    private func sendPacket(_ payload: Data, sequence: UInt8) async throws {
        try await transport.write(MySQLPacket(sequence: sequence, payload: payload).encoded())
    }

    private func readPacket() async throws -> MySQLPacket {
        let packet = try await transport.readPacket(expectedSequence: packetSequence)
        packetSequence = packet.sequence &+ 1
        return packet
    }

    private static let maximumColumnCount = 4096
    private static let maximumResultSets = 1024
}
