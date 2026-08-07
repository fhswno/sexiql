import Foundation
import SQLCore

public protocol DatabaseConnection: Sendable {
    var profile: ConnectionProfile { get }

    func isConnected() async -> Bool
    func connect(password: String?) async throws
    func disconnect() async throws

    func execute(_ sql: String) async throws -> QueryResult
    func execute(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult

    func stream(_ sql: String) async throws -> StreamedQuery

    func serverVersion() async throws -> String?

    func cancelInFlight() async
}

public extension DatabaseConnection {
    func cancelInFlight() async {}
}

public extension DatabaseConnection {
    func execute(_ sql: String) async throws -> QueryResult {
        try await execute(sql, parameters: [])
    }
}

public struct ConnectionFactory: Sendable {
    public init() {}

    public func makeConnection(for profile: ConnectionProfile) -> any DatabaseConnection {
        switch profile.kind {
        case .postgres: PostgresConnection(profile: profile)
        case .mysql: MySQLConnection(profile: profile)
        case .sqlite: SQLiteConnection(profile: profile)
        }
    }
}
