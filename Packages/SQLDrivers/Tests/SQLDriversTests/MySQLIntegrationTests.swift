import XCTest
@testable import SQLDrivers
import SQLCore

final class MySQLIntegrationTests: XCTestCase {
    func testLiveConnectQueryAndStream() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["SEXIQL_TEST_MYSQL_URL"],
              let url = URL(string: urlString),
              let host = url.host,
              let username = url.user, !username.isEmpty else {
            return
        }
        let database = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let profile = ConnectionProfile(
            name: "mysql-integration",
            kind: .mysql,
            host: host,
            port: url.port ?? 3306,
            database: database,
            username: username,
            tlsMode: .preferred
        )
        let connection = MySQLConnection(profile: profile)
        try await connection.connect(password: url.password)
        let version = try await connection.serverVersion()
        XCTAssertNotNil(version)

        let result = try await connection.execute("SELECT 42 AS answer")
        XCTAssertEqual(result.rows.first?.values.first, .int(42))

        let streamed = try await connection.stream("SELECT 1 AS n UNION ALL SELECT 2 AS n")
        var rows = 0
        for try await _ in streamed.rows { rows += 1 }
        XCTAssertEqual(rows, 2)
        try await connection.disconnect()
    }
}
