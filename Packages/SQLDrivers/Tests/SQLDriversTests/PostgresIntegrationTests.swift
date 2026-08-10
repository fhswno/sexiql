import XCTest
@testable import SQLDrivers
import SQLCore

final class PostgresIntegrationTests: XCTestCase {
    func testLiveConnectQueryAndStream() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["SEXIQL_TEST_PG_URL"],
              let url = URL(string: urlString),
              let host = url.host,
              let port = url.port,
              let username = url.user, !username.isEmpty else {
            return
        }
        let database = url.lastPathComponent.isEmpty ? "postgres" : url.lastPathComponent

        let profile = ConnectionProfile(
            name: "integration",
            kind: .postgres,
            host: host,
            port: port,
            database: database,
            username: username
        )
        let connection = PostgresConnection(profile: profile)
        try await connection.connect(password: url.password)

        let version = try await connection.serverVersion()
        XCTAssertNotNil(version)
        XCTAssertTrue(version!.hasPrefix("1") || version!.hasPrefix("9") || version!.hasPrefix("1") || version!.contains("."))

        let result = try await connection.execute("SELECT 42 AS answer, 'hello' AS greeting, NULL AS nothing, true AS flag")
        XCTAssertTrue(result.isResultSet)
        XCTAssertEqual(result.columns?.map(\.name), ["answer", "greeting", "nothing", "flag"])
        XCTAssertEqual(result.rows.first?.values, [.int(42), .string("hello"), .null, .bool(true)])

        let streamed = try await connection.stream("SELECT generate_series(1, 5) AS n")
        var count = 0
        for try await _ in streamed.rows {
            count += 1
        }
        XCTAssertEqual(count, 5)

        do {
            _ = try await connection.execute("SELECT * FROM sexiql_no_such_table")
            XCTFail("expected an error")
        } catch let error as PGError {
            XCTAssertEqual(error.code, "42P01")
        } catch {
            XCTFail("unexpected error \(error)")
        }

        try await connection.disconnect()
        let connected = await connection.isConnected()
        XCTAssertFalse(connected)
    }
}
