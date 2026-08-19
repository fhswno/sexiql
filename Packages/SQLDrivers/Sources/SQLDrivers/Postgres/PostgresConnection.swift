import Foundation
import SQLCore

public actor PostgresConnection: DatabaseConnection {
    public let profile: ConnectionProfile

    private let transport = PostgresTransport()
    private var buffer = Data()
    private var serverParameters: [String: String] = [:]
    private var connected = false
    private var password: String?
    private var backendProcessID: Int32?
    private var backendSecretKey: Int32?

    private enum AuthStage {
        case idle
        case scramAwaitingContinue(SCRAMClient)
        case scramAwaitingFinal(SCRAMClient, expectedServerSignature: Data)
    }

    private var authStage: AuthStage = .idle

    private var queryOperationBusy = false
    private var queryOperationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(profile: ConnectionProfile) {
        self.profile = profile
    }

    public func isConnected() async -> Bool {
        connected
    }

    public func connect(password: String?) async throws {
        guard !connected else { return }
        self.password = password
        buffer.removeAll()
        serverParameters = [:]
        authStage = .idle

        do {
            try await performHandshake()
            connected = true
        } catch {
            await transport.close()
            buffer.removeAll()
            throw error
        }
    }

    public func disconnect() async throws {
        if connected {
            try? await sendRaw(PGWire.frame(PGMessageType.terminate.rawValue, Data()))
        }
        await transport.close()
        buffer.removeAll()
        connected = false
        password = nil
        backendProcessID = nil
        backendSecretKey = nil
    }

    public func cancelInFlight() async {
        guard connected, let pid = backendProcessID, let key = backendSecretKey else {
            await markDisconnected()
            return
        }
        let sent = await sendCancelRequest(processID: pid, secretKey: key)
        if !sent {
            await markDisconnected()
        }
    }

    private func sendCancelRequest(processID: Int32, secretKey: Int32) async -> Bool {
        let host = profile.host
        let port = profile.port
        let tlsMode = profile.tlsMode
        let tlsServerName = profile.tlsServerName ?? profile.host
        let packet = PGWire.cancelRequest(processID: processID, secretKey: secretKey)
        let side = PostgresTransport()
        var sent = false
        do {
            try await side.connect(host: host, port: port)
            if tlsMode != .off {
                var sslRequest = PGWire.int32(8)
                sslRequest.append(PGWire.int32(80877103))
                try await side.write(sslRequest)
                let flag = try await side.readExact(1)
                if flag.first == UInt8(ascii: "S") {
                    try await side.startTLS(
                        serverName: tlsServerName,
                        verifyCertificate: tlsMode.verifiesCertificate
                    )
                }
            }
            try await side.write(packet)
            sent = true
        } catch {
            sent = false
        }
        await side.close()
        return sent
    }

    // MARK: - Query

    public func execute(_ sql: String) async throws -> QueryResult {
        try requireConnected()
        await beginQueryOperation()
        defer { endQueryOperation() }
        try await sendMessage(.query, PGQueryMessages.simpleQueryPayload(sql))

        var columns: [SQLColumn]?
        var rows: [SQLRow] = []
        var commandTag: String?

        while true {
            let (type, payload) = try await readMessage()
            switch type {
            case .rowDescription:
                columns = try PGRowCodec.parseRowDescription(payload)
            case .dataRow:
                guard let columns else { throw PGWireError.invalidMessage }
                rows.append(try PGRowCodec.parseDataRow(payload, columns: columns))
            case .commandComplete:
                commandTag = PGRowCodec.parseCommandTag(payload)
            case .emptyQueryResponse:
                return QueryResult()
            case .noticeResponse, .parameterStatus, .notificationResponse:
                continue
            case .errorResponse:
                let error = try PGRowCodec.parseErrorResponse(payload)
                try await drainUntilReady()
                throw error
            case .readyForQuery:
                if let columns {
                    return QueryResult(columns: columns, rows: rows)
                }
                return QueryResult(affectedRowCount: PGRowCodec.affectedRows(from: commandTag))
            default:
                try await failProtocol(type, context: "query")
            }
        }
    }

    public func execute(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        try requireConnected()
        await beginQueryOperation()
        defer { endQueryOperation() }
        try await sendParameterizedQuery(sql, parameters: parameters)

        var columns: [SQLColumn]?
        var rows: [SQLRow] = []
        var commandTag: String?

        while true {
            let (type, payload) = try await readMessage()
            switch type {
            case .parseComplete, .bindComplete, .closeComplete, .parameterDescription, .noData:
                continue
            case .rowDescription:
                columns = try PGRowCodec.parseRowDescription(payload)
            case .dataRow:
                guard let columns else { throw PGWireError.invalidMessage }
                rows.append(try PGRowCodec.parseDataRow(payload, columns: columns))
            case .commandComplete:
                commandTag = PGRowCodec.parseCommandTag(payload)
            case .noticeResponse, .parameterStatus, .notificationResponse:
                continue
            case .errorResponse:
                let error = try PGRowCodec.parseErrorResponse(payload)
                try await drainUntilReady()
                throw error
            case .readyForQuery:
                if let columns {
                    return QueryResult(columns: columns, rows: rows)
                }
                return QueryResult(affectedRowCount: PGRowCodec.affectedRows(from: commandTag))
            default:
                try await failProtocol(type, context: "parameterized query")
            }
        }
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
        try await sendMessage(.query, PGQueryMessages.simpleQueryPayload(sql))

        var columns: [SQLColumn] = []
        while true {
            let (type, payload) = try await readMessage()
            switch type {
            case .rowDescription:
                columns = try PGRowCodec.parseRowDescription(payload)
                handedOff = true
                let stream = makeRowStream(columns: columns)
                return StreamedQuery(columns: columns, rows: stream)
            case .commandComplete:
                continue
            case .emptyQueryResponse:
                return StreamedQuery(columns: [], rows: RowStream { $0.finish() })
            case .noticeResponse, .parameterStatus, .notificationResponse:
                continue
            case .errorResponse:
                let error = try PGRowCodec.parseErrorResponse(payload)
                try await drainUntilReady()
                throw error
            case .readyForQuery:
                return StreamedQuery(columns: [], rows: RowStream { $0.finish() })
            default:
                try await failProtocol(type, context: "query")
            }
        }
    }

    private func makeRowStream(columns: [SQLColumn]) -> RowStream {
        RowStream { continuation in
            Task {
                do {
                    while true {
                        let (type, payload) = try await self.readMessage()
                        switch type {
                        case .dataRow:
                            continuation.yield(try PGRowCodec.parseDataRow(payload, columns: columns))
                        case .commandComplete, .noticeResponse, .parameterStatus, .notificationResponse:
                            continue
                        case .errorResponse:
                            let error = try PGRowCodec.parseErrorResponse(payload)
                            try await self.drainUntilReady()
                            throw error
                        case .readyForQuery:
                            continuation.finish()
                            await self.endQueryOperation()
                            return
                        default:
                            try await self.failProtocol(type, context: "streaming")
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    await self.endQueryOperation()
                }
            }
        }
    }

    private func drainUntilReady() async throws {
        while true {
            let (type, _) = try await readMessage()
            switch type {
            case .readyForQuery:
                return
            case .noticeResponse, .commandComplete, .emptyQueryResponse,
                 .parseComplete, .bindComplete, .closeComplete, .noData,
                 .parameterDescription, .rowDescription, .dataRow,
                 .parameterStatus, .notificationResponse, .portalSuspended:
                continue
            case .errorResponse:
                continue
            default:
                continue
            }
        }
    }

    private func failProtocol(_ type: PGMessageType, context: String) async throws -> Never {
        try? await drainUntilReady()
        throw PGError(
            code: "08P01",
            message: "Unexpected message \(Self.describe(type)) during \(context)"
        )
    }

    private static func describe(_ type: PGMessageType) -> String {
        switch type {
        case .bindComplete: "BindComplete"
        case .parseComplete: "ParseComplete"
        case .closeComplete: "CloseComplete"
        case .portalSuspended: "PortalSuspended"
        case .noData: "NoData"
        case .parameterDescription: "ParameterDescription"
        case .notificationResponse: "NotificationResponse"
        case .parameterStatus: "ParameterStatus"
        case .commandComplete: "CommandComplete"
        case .readyForQuery: "ReadyForQuery"
        case .rowDescription: "RowDescription"
        case .dataRow: "DataRow"
        case .errorResponse: "ErrorResponse"
        case .noticeResponse: "NoticeResponse"
        default: "0x\(String(type.rawValue, radix: 16)) (\(type.rawValue))"
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

    public func serverVersion() async throws -> String? {
        try requireConnected()
        return serverParameters["server_version"]
    }

    // MARK: - Transport helpers

    private func requireConnected() throws {
        guard connected else {
            throw SQLDriverError.connectionFailed(message: "Not connected")
        }
    }

    private func sendParameterizedQuery(_ sql: String, parameters: [SQLValue]) async throws {
        let payloads = PGQueryMessages.extendedQuery(sql: sql, parameters: parameters)
        try await sendMessage(.parse, payloads.parse)
        try await sendMessage(.bind, payloads.bind)
        try await sendMessage(.describe, payloads.describe)
        try await sendMessage(.execute, payloads.execute)
        try await sendMessage(.sync, payloads.sync)
    }

    private func sendMessage(_ type: PGMessageType, _ payload: Data) async throws {
        try await sendRaw(PGWire.frame(type.rawValue, payload))
    }

    private func sendRaw(_ data: Data) async throws {
        do {
            try await transport.write(data)
        } catch {
            await markDisconnected()
            throw error
        }
    }

    private func readExact(_ count: Int) async throws -> Data {
        while buffer.count < count {
            let chunk: Data
            do {
                chunk = try await transport.readExact(max(count - buffer.count, 1))
            } catch {
                await markDisconnected()
                throw error
            }
            guard !chunk.isEmpty else {
                await markDisconnected()
                throw PGError(code: "08006", message: "Connection closed by server")
            }
            buffer.append(chunk)
        }
        defer { buffer.removeFirst(count) }
        return Data(buffer.prefix(count))
    }

    private func markDisconnected() async {
        connected = false
        buffer.removeAll()
        await transport.close()
    }

    private func readMessage() async throws -> (PGMessageType, Data) {
        let header = try await readExact(5)
        let type = PGMessageType(rawValue: header[header.startIndex])
        var reader = PGByteReader(data: header, offset: 1)
        let length = Int(try reader.readInt32())
        guard length >= 4, length <= 64 * 1024 * 1024 else {
            throw PGWireError.invalidMessage
        }
        let payload = try await readExact(length - 4)
        return (type, payload)
    }

    // MARK: - Handshake (libpq-compatible)

    private func performHandshake() async throws {
        guard !profile.host.isEmpty, profile.port > 0 else {
            throw PGError(code: "08001", message: "Postgres host and port are required")
        }

        try await transport.connect(host: profile.host, port: profile.port)

        switch profile.tlsMode {
        case .off:
            break

        case .preferred, .required, .verifyFull:
            let offersTLS = try await askServerForTLS()
            if offersTLS {
                try await transport.startTLS(
                    serverName: profile.tlsServerName ?? profile.host,
                    verifyCertificate: profile.tlsMode.verifiesCertificate
                )
            } else if profile.tlsMode == .required || profile.tlsMode == .verifyFull {
                await transport.close()
                throw PGError(
                    code: "28000",
                    message: "Server does not support TLS, but TLS is required"
                )
            }
        }

        try await sendStartupMessage()
        try await readUntilReady()
    }

    private func askServerForTLS() async throws -> Bool {
        var sslRequest = PGWire.int32(8)
        sslRequest.append(PGWire.int32(80877103))
        try await sendRaw(sslRequest)

        let response = try await readExact(1)
        let code = response[response.startIndex]
        switch code {
        case 0x53: // 'S'
            return true
        case 0x4E: // 'N'
            return false
        case 0x45: // 'E'
            throw PGError(code: "SSL", message: "Server rejected the SSL request")
        default:
            throw PGError(
                code: "SSL",
                message: "Unexpected SSL negotiation response (0x\(String(code, radix: 16)))"
            )
        }
    }

    private func sendStartupMessage() async throws {
        var payload = Data()
        payload.append(PGWire.int32(196608))
        var parameters: [(String, String)] = [
            ("user", profile.username),
            ("application_name", "SexiQL"),
            ("client_encoding", "UTF8"),
        ]
        let database = profile.resolvedDatabase
        if !database.isEmpty {
            parameters.insert(("database", database), at: 1)
        }
        for (name, value) in parameters {
            payload.append(PGWire.cstring(name))
            payload.append(PGWire.cstring(value))
        }
        payload.append(0)
        try await sendRaw(PGWire.frameUntagged(payload))
    }

    private func readUntilReady() async throws {
        while true {
            let (type, payload) = try await readMessage()
            switch type {
            case .authentication:
                try await handleAuthentication(payload: payload)
            case .backendKeyData:
                var reader = PGByteReader(data: payload)
                backendProcessID = try reader.readInt32()
                backendSecretKey = try reader.readInt32()
            case .parameterStatus:
                var reader = PGByteReader(data: payload)
                let name = try reader.readCString()
                let value = try reader.readCString()
                serverParameters[name] = value
            case .noticeResponse:
                continue
            case .errorResponse:
                throw try PGRowCodec.parseErrorResponse(payload)
            case .readyForQuery:
                return
            default:
                throw PGError(code: "08P01", message: "Unexpected message \(type.rawValue) during startup")
            }
        }
    }

    private func handleAuthentication(payload: Data) async throws {
        var reader = PGByteReader(data: payload)
        let code = try reader.readInt32()
        switch code {
        case 0:
            authStage = .idle
        case 3:
            guard let password else { throw PGError(code: "28P01", message: "No password available") }
            try await sendMessage(.passwordMessage, PGWire.cstring(password))
        case 5:
            guard let password, !profile.username.isEmpty else {
                throw PGError(code: "28P01", message: "No credentials available")
            }
            let salt = try reader.readBytes(4)
            let response = pgMD5Password(password: password, username: profile.username, salt: salt)
            try await sendMessage(.passwordMessage, PGWire.cstring(response))
        case 10:
            let mechanisms = try PGRowCodec.readSASLMechanisms(reader: reader)
            guard mechanisms.contains("SCRAM-SHA-256"), !profile.username.isEmpty, let password else {
                throw PGWireError.unsupportedAuth
            }
            let client = SCRAMClient(username: profile.username, password: password)
            authStage = .scramAwaitingContinue(client)
            var response = PGWire.cstring("SCRAM-SHA-256")
            let firstMessage = Data(client.clientFirstMessage().utf8)
            response.append(PGWire.int32(Int32(firstMessage.count)))
            response.append(firstMessage)
            try await sendMessage(.passwordMessage, response)
        case 11:
            guard case .scramAwaitingContinue(let client) = authStage else {
                throw PGWireError.invalidMessage
            }
            let serverFirst = String(decoding: payload[reader.offset...], as: UTF8.self)
            let parsed = try SCRAMClient.parseServerFirst(serverFirst)
            let result = try client.clientFinalMessage(serverFirst: parsed)
            authStage = .scramAwaitingFinal(client, expectedServerSignature: result.serverSignature)
            try await sendMessage(.passwordMessage, Data(result.clientFinal.utf8))
        case 12:
            guard case .scramAwaitingFinal(_, let expectedServerSignature) = authStage else {
                throw PGWireError.invalidMessage
            }
            let serverFinal = String(decoding: payload[reader.offset...], as: UTF8.self)
            guard SCRAMClient.verifyServerFinal(serverFinal, expected: expectedServerSignature) else {
                throw PGError(code: "28000", message: "SCRAM server signature verification failed")
            }
            authStage = .idle
        default:
            throw PGWireError.unsupportedAuth
        }
    }
}

// MARK: - Test-facing aliases (stable names used by existing unit tests)

extension PostgresConnection {
    static func parseErrorResponse(_ payload: Data) throws -> PGError {
        try PGRowCodec.parseErrorResponse(payload)
    }

    static func affectedRows(from tag: String?) -> Int? {
        PGRowCodec.affectedRows(from: tag)
    }

    static func parseRowDescription(_ payload: Data) throws -> [SQLColumn] {
        try PGRowCodec.parseRowDescription(payload)
    }

    static func parseDataRow(_ payload: Data, columns: [SQLColumn]) throws -> SQLRow {
        try PGRowCodec.parseDataRow(payload, columns: columns)
    }

    static func textEncoding(_ value: SQLValue) -> String {
        PGRowCodec.textEncoding(value)
    }
}
