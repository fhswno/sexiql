import XCTest
@testable import SQLDrivers
import SQLCore
import Synchronization

final class MockConnection: DatabaseConnection, @unchecked Sendable {
    private struct State {
        var connected = false
        var version: String?
        var failureMessage: String?
        var receivedPassword: String?
        var queryHandler: (@Sendable (String) throws -> QueryResult)?
    }

    private let state = Mutex<State>(State())

    let profile: ConnectionProfile

    init(profile: ConnectionProfile, version: String? = "9.9") {
        self.profile = profile
        state.withLock { $0.version = version }
    }

    func setFailure(_ error: Error) {
        state.withLock { $0.failureMessage = error.localizedDescription }
    }

    func setQueryHandler(_ handler: @escaping @Sendable (String) throws -> QueryResult) {
        state.withLock { $0.queryHandler = handler }
    }

    func lastPassword() -> String? {
        state.withLock { $0.receivedPassword }
    }

    func isConnected() async -> Bool {
        state.withLock { $0.connected }
    }

    func markDisconnected() {
        state.withLock { $0.connected = false }
    }

    func connect(password: String?) async throws {
        try state.withLock { state in
            state.receivedPassword = password
            if let failureMessage = state.failureMessage {
                throw SQLDriverError.connectionFailed(message: failureMessage)
            }
            state.connected = true
        }
    }

    func disconnect() async throws {
        state.withLock { $0.connected = false }
    }

    func execute(_ sql: String) async throws -> QueryResult {
        try state.withLock { state in
            if let failureMessage = state.failureMessage {
                throw SQLDriverError.connectionFailed(message: failureMessage)
            }
            return try state.queryHandler?(sql) ?? QueryResult(affectedRowCount: 0)
        }
    }

    func execute(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        try await execute(sql)
    }

    func stream(_ sql: String) async throws -> StreamedQuery {
        let columns = try await execute(sql).columns ?? []
        return StreamedQuery(columns: columns, rows: RowStream { c in c.finish() })
    }

    func serverVersion() async throws -> String? {
        state.withLock { $0.version }
    }

    func cancelInFlight() async {}
}

final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let state = Mutex<[UUID: String]>([:])

    func setPassword(_ password: String, for profileID: UUID) throws {
        state.withLock { $0[profileID] = password }
    }

    func password(for profileID: UUID) throws -> String? {
        state.withLock { $0[profileID] }
    }

    func deletePassword(for profileID: UUID) throws {
        state.withLock { $0[profileID] = nil }
    }
}

final class ConnectionManagerTests: XCTestCase {
    func testConnectDisconnectLifecycle() async throws {
        let store = MemoryCredentialStore()
        let manager = ConnectionManager(credentialStore: store)
        let profile = ConnectionProfile(name: "m", kind: .postgres, host: "h", username: "u")

        var status = await manager.status(for: profile.id)
        XCTAssertEqual(status, .disconnected)

        try store.setPassword("pw", for: profile.id)
        let mock = MockConnection(profile: profile)
        stubFactory(mock)
        let connection = try await manager.connect(profile)
        status = await manager.status(for: profile.id)
        XCTAssertEqual(status, .connected)
        XCTAssertEqual(mock.lastPassword(), "pw")

        let second = try await manager.connect(profile)
        XCTAssertTrue(second as AnyObject === connection as AnyObject, "reconnect should reuse the session")

        try await manager.disconnect(profile.id)
        status = await manager.status(for: profile.id)
        XCTAssertEqual(status, .disconnected)
        clearFactory()
    }

    func testConnectRebuildsWhenDisconnected() async throws {
        let store = MemoryCredentialStore()
        let manager = ConnectionManager(credentialStore: store)
        let profile = ConnectionProfile(name: "m", kind: .postgres, host: "h", username: "u")

        let first = MockConnection(profile: profile)
        stubFactory(first)
        let original = try await manager.connect(profile)
        let firstConnected = await first.isConnected()
        XCTAssertTrue(firstConnected)

        first.markDisconnected()
        let firstDead = await first.isConnected()
        XCTAssertFalse(firstDead)

        let replacement = MockConnection(profile: profile)
        stubFactory(replacement)
        let second = try await manager.connect(profile)
        let replacementConnected = await replacement.isConnected()
        XCTAssertTrue(replacementConnected)
        XCTAssertTrue(second as AnyObject === replacement as AnyObject)
        XCTAssertFalse(second as AnyObject === original as AnyObject)
        clearFactory()
    }

    func testFailedConnectRecordsFailure() async throws {
        let store = MemoryCredentialStore()
        let manager = ConnectionManager(credentialStore: store)
        let profile = ConnectionProfile(name: "m", kind: .postgres, host: "h")

        let mock = MockConnection(profile: profile)
        stubFactory(mock)
        mock.setFailure(SQLDriverError.connectionFailed(message: "refused"))

        do {
            _ = try await manager.connect(profile)
            XCTFail("expected failure")
        } catch {
            let status = await manager.status(for: profile.id)
            guard case .failed = status else {
                XCTFail("expected failed status, got \(status)")
                return
            }
        }
        clearFactory()
    }

    func testExecuteThroughManager() async throws {
        let store = MemoryCredentialStore()
        let manager = ConnectionManager(credentialStore: store)
        let profile = ConnectionProfile(name: "m", kind: .postgres, host: "h")

        let mock = MockConnection(profile: profile)
        stubFactory(mock)
        mock.setQueryHandler { sql in
            QueryResult(columns: [SQLColumn(name: "v", dataType: "int4", ordinal: 0)], rows: [SQLRow(values: [.int(7)])])
        }

        _ = try await manager.connect(profile)
        let connection = try requireConnection(await manager.connection(for: profile.id))
        let result = try await connection.execute("SELECT 7")
        XCTAssertEqual(result.rows.first?.values.first, .int(7))

        let version = try await connection.serverVersion()
        XCTAssertEqual(version, "9.9")
        clearFactory()
    }

    private func stubFactory(_ mock: MockConnection) {
        ConnectionFactoryHook.factory = { _ in mock }
    }

    private func clearFactory() {
        ConnectionFactoryHook.factory = nil
    }

    private func requireConnection(_ connection: (any DatabaseConnection)?) throws -> any DatabaseConnection {
        guard let connection else {
            throw NSError(domain: "ConnectionManagerTests", code: 1)
        }
        return connection
    }
}
