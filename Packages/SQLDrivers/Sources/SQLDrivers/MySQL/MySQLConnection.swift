import Foundation
import SQLCore

public actor MySQLConnection: DatabaseConnection {
    public let profile: ConnectionProfile

    private let transport = MySQLTransport()
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
        let side = MySQLConnection(profile: profile)
        do {
            try await side.connect(password: password)
            do {
                _ = try await side.execute(MySQLCancel.killQuerySQL(connectionID: connectionID))
            } catch let error as MySQLWireError where MySQLCancel.isBenignKillError(error) {
                // Query already finished.
            }
            try? await side.disconnect()
        } catch {
            await hardClose()
        }
    }

    public func execute(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        try requireConnected()
        await beginQueryOperation()
        defer { endQueryOperation() }
        if parameters.isEmpty {
            try await sendCommand(MySQLPrepared.comQuery, payload: Data(sql.utf8))
            let start = try await readResultStart(binaryRows: false)
            if let affected = start.affectedRows {
                return QueryResult(affectedRowCount: affected)
            }
            var rows: [SQLRow] = []
            while let row = try await readNextRow(columns: start.columns, binary: false) {
                rows.append(row)
            }
            return QueryResult(columns: start.columns, rows: rows)
        }

        return try await executePrepared(sql, parameters: parameters)
    }

    public func stream(_ sql: String) async throws -> StreamedQuery {
        try requireConnected()
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
            return StreamedQuery(columns: [], rows: RowStream { $0.finish() })
        }
        handedOff = true
        return StreamedQuery(columns: columns, rows: makeRowStream(columns: columns))
    }

    public func serverVersion() async throws -> String? {
        try requireConnected()
        return handshake?.serverVersion
    }

    private func makeRowStream(columns: [SQLColumn]) -> RowStream {
        RowStream { continuation in
            Task {
                do {
                    while let row = try await self.readNextRow(columns: columns, binary: false) {
                        continuation.yield(row)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await self.endQueryOperation()
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

    // MARK: - Result sets

    private struct ResultStart {
        var columns: [SQLColumn]?
        var affectedRows: Int?
        var binaryRows: Bool
    }

    private func readResultStart(binaryRows: Bool) async throws -> ResultStart {
        let packet = try await readPacket()
        guard let first = packet.payload.first else { throw MySQLWireError.invalidPacket }
        if first == 0xff {
            throw try MySQLAuth.parseError(packet.payload)
        }
        if first == 0x00 {
            let ok = try MySQLAuth.parseOK(packet.payload)
            return ResultStart(columns: nil, affectedRows: Int(ok.affectedRows), binaryRows: binaryRows)
        }

        var reader = MySQLByteReader(data: packet.payload)
        guard let count = try reader.readLengthEncodedInteger(), count <= UInt64(Int.max) else {
            throw MySQLWireError.invalidPacket
        }
        var definitions: [MySQLColumnDefinition] = []
        definitions.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            let definitionPacket = try await readPacket()
            definitions.append(try MySQLColumnDefinition.parse(definitionPacket.payload))
        }
        _ = try await readPacket()
        let columns = MySQLRowCodec.columns(from: definitions)
        return ResultStart(columns: columns, affectedRows: nil, binaryRows: binaryRows)
    }

    private func readNextRow(columns: [SQLColumn]?, binary: Bool) async throws -> SQLRow? {
        guard let columns else { return nil }
        let packet = try await readPacket()
        guard let first = packet.payload.first else { throw MySQLWireError.invalidPacket }
        if first == 0xff { throw try MySQLAuth.parseError(packet.payload) }
        if MySQLRowCodec.isTerminator(packet.payload) { return nil }
        return try binary
            ? MySQLRowCodec.parseBinaryRow(packet.payload, columns: columns)
            : MySQLRowCodec.parseTextRow(packet.payload, columns: columns)
    }

    // MARK: - Prepared statements

    private func executePrepared(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        try await sendCommand(MySQLPrepared.comStmtPrepare, payload: Data(sql.utf8))
        let prepared = try await readPacket()
        guard prepared.payload.first == 0x00 else { throw try MySQLAuth.parseError(prepared.payload) }
        var reader = MySQLByteReader(data: prepared.payload, offset: 1)
        let statementID = try reader.readUInt32()
        let columnCount = Int(try reader.readUInt16())
        let parameterCount = Int(try reader.readUInt16())
        if parameterCount > 0 {
            _ = try await readPacket()
            for _ in 0..<parameterCount { _ = try await readPacket() }
            _ = try await readPacket()
        }
        if columnCount > 0 {
            for _ in 0..<columnCount { _ = try await readPacket() }
            _ = try await readPacket()
        }

        try await sendCommand(
            MySQLPrepared.comStmtExecute,
            payload: MySQLPrepared.buildExecutePayload(statementID: statementID, parameters: parameters)
        )
        let start = try await readResultStart(binaryRows: true)
        if let affected = start.affectedRows {
            try? await closePrepared(statementID)
            return QueryResult(affectedRowCount: affected)
        }
        var rows: [SQLRow] = []
        while let row = try await readNextRow(columns: start.columns, binary: true) {
            rows.append(row)
        }
        try? await closePrepared(statementID)
        return QueryResult(columns: start.columns, rows: rows)
    }

    private func closePrepared(_ statementID: UInt32) async throws {
        try await sendCommand(MySQLPrepared.comStmtClose, payload: MySQLWire.uint32(statementID))
    }

    // MARK: - Packet helpers

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
}
