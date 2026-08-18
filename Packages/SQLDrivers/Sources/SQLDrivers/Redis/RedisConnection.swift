import Foundation
import SQLCore

public actor RedisConnection: DatabaseConnection {
    public let profile: ConnectionProfile

    private let transport = RedisTransport()
    private var decoder = RedisDecoder(data: Data())
    private var connected = false
    private var password: String?

    public init(profile: ConnectionProfile) {
        self.profile = profile
    }

    public func isConnected() async -> Bool { connected }

    public func connect(password: String?) async throws {
        guard !connected else { return }
        guard !profile.host.isEmpty, profile.port > 0 else {
            throw SQLDriverError.connectionFailed(message: "Redis host and port are required")
        }
        self.password = password
        decoder = RedisDecoder(data: Data())
        do {
            try await transport.connect(host: profile.host, port: profile.port)
            if profile.tlsMode != .off {
                try await transport.startTLS(
                    serverName: profile.tlsServerName ?? profile.host,
                    verifyCertificate: profile.tlsMode.verifiesCertificate
                )
            }
            if let password, !password.isEmpty {
                if profile.username.isEmpty {
                    _ = try await send(["AUTH", password])
                } else {
                    _ = try await send(["AUTH", profile.username, password])
                }
            } else if !profile.username.isEmpty {
                throw SQLDriverError.connectionFailed(message: "Redis ACL username requires a password")
            }
            if let index = logicalDatabase, index > 0 {
                _ = try await send(["SELECT", String(index)])
            }
            _ = try await send(["PING"])
            connected = true
        } catch {
            await transport.close()
            connected = false
            throw error
        }
    }

    public func disconnect() async throws {
        if connected {
            try? await transport.write(RedisCommand.encode(["QUIT"]))
        }
        await transport.close()
        connected = false
        decoder = RedisDecoder(data: Data())
    }

    public func cancelInFlight() async {
        await transport.close()
        connected = false
        decoder = RedisDecoder(data: Data())
    }

    public func execute(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        try requireConnected()
        let tokens = tokens(for: sql, parameters: parameters)
        guard !tokens.isEmpty else { return QueryResult() }
        let reply = try await send(tokens)
        return try RedisResultGrid.queryResult(for: reply, command: tokens)
    }

    public func stream(_ sql: String) async throws -> StreamedQuery {
        let result = try await execute(sql)
        let columns = result.columns ?? []
        let rows = result.rows
        return StreamedQuery(
            columns: columns,
            rows: RowStream { continuation in
                for row in rows {
                    continuation.yield(row)
                }
                continuation.finish()
            }
        )
    }

    public func serverVersion() async throws -> String? {
        try requireConnected()
        let reply = try await send(["INFO", "server"])
        guard let text = reply.string else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("redis_version:") {
                return String(line.dropFirst("redis_version:".count))
            }
        }
        return text
    }

    public static let defaultScanCap = 2000

    public struct ScanResult: Sendable {
        public var keys: [String]
        public var truncated: Bool
    }

    public static func scanShouldStop(keyCount: Int, cap: Int, cursor: String) -> Bool {
        cursor == "0" || keyCount >= cap
    }

    public func scanKeys(count: Int = 200, cap: Int = defaultScanCap) async throws -> ScanResult {
        try requireConnected()
        var cursor = "0"
        var keys: [String] = []
        var truncated = false
        repeat {
            let reply = try await send(["SCAN", cursor, "COUNT", String(count)])
            guard case .array(let items) = reply, let items, items.count >= 2 else {
                throw RedisError.protocolError("Unexpected SCAN reply")
            }
            cursor = items[0].string ?? "0"
            if case .array(let batch) = items[1], let batch {
                for item in batch {
                    if let key = item.string, !key.isEmpty {
                        keys.append(key)
                        if keys.count >= cap {
                            truncated = cursor != "0"
                            cursor = "0"
                            break
                        }
                    }
                }
            }
        } while !Self.scanShouldStop(keyCount: keys.count, cap: cap, cursor: cursor)
        if keys.count >= cap, cursor != "0" {
            truncated = true
        }
        return ScanResult(keys: keys, truncated: truncated)
    }

    public func keyTypeAndTTL(_ key: String) async throws -> (type: String, ttl: Int64) {
        try requireConnected()
        let type = try await send(["TYPE", key]).string ?? "none"
        let ttlReply = try await send(["TTL", key])
        let ttl: Int64
        if case .integer(let value) = ttlReply {
            ttl = value
        } else {
            ttl = -1
        }
        return (type, ttl)
    }

    private var logicalDatabase: Int? {
        let raw = profile.database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return 0 }
        return Int(raw)
    }

    private func requireConnected() throws {
        guard connected else { throw SQLDriverError.connectionFailed(message: "Not connected") }
    }

    private func tokens(for sql: String, parameters: [SQLValue]) -> [String] {
        var tokens = RedisCommand.tokenize(sql)
        if !parameters.isEmpty {
            tokens.append(contentsOf: parameters.map(Self.parameterText))
        }
        return tokens
    }

    private static func parameterText(_ value: SQLValue) -> String {
        switch value {
        case .null: ""
        case .bool(let flag): flag ? "1" : "0"
        case .int(let number): String(number)
        case .double(let number): String(number)
        case .string(let text): text
        case .data(let data): String(data: data, encoding: .utf8) ?? ""
        case .date(let date): ISO8601DateFormatter().string(from: date)
        }
    }

    private func send(_ arguments: [String]) async throws -> RedisReply {
        try await transport.write(RedisCommand.encode(arguments))
        while true {
            if let reply = try decoder.consumeReply() {
                if case .error(let message) = reply {
                    throw RedisError.serverError(message)
                }
                return reply
            }
            decoder.append(try await transport.readSome(max: 16 * 1024))
        }
    }
}
