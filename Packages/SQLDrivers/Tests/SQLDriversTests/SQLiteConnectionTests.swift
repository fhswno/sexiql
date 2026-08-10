import XCTest
@testable import SQLDrivers
import SQLCore

final class SQLiteConnectionTests: XCTestCase {
    private var dbPath: String!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteConnectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("test.sqlite").path
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func makeConnection() -> SQLiteConnection {
        SQLiteConnection(profile: ConnectionProfile(name: "local", kind: .sqlite, database: dbPath))
    }

    func testConnectAndServerVersion() async throws {
        let connection = makeConnection()
        var connected = await connection.isConnected()
        XCTAssertFalse(connected)
        try await connection.connect(password: nil)
        connected = await connection.isConnected()
        XCTAssertTrue(connected)
        let version = try await connection.serverVersion()
        XCTAssertNotNil(version)
        XCTAssertTrue(version!.hasPrefix("3."))
        try await connection.disconnect()
        connected = await connection.isConnected()
        XCTAssertFalse(connected)
    }

    func testExecuteDDLAndQuery() async throws {
        let connection = makeConnection()
        try await connection.connect(password: nil)

        _ = try await connection.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL, active BOOLEAN)")
        let insert = try await connection.execute("INSERT INTO users (name, score, active) VALUES ('ada', 9.5, 1), ('bob', 3.25, 0)")
        XCTAssertEqual(insert.affectedRowCount, 2)

        let result = try await connection.execute("SELECT id, name, score, active FROM users ORDER BY id")
        XCTAssertTrue(result.isResultSet)
        XCTAssertEqual(result.columns?.map(\.name), ["id", "name", "score", "active"])
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result[0, 1], .string("ada"))
        XCTAssertEqual(result[0, 2], .double(9.5))
        XCTAssertEqual(result[1, 3], .int(0))
    }

    func testNullsAndBlobs() async throws {
        let connection = makeConnection()
        try await connection.connect(password: nil)
        _ = try await connection.execute("CREATE TABLE t (a TEXT, b BLOB)")
        _ = try await connection.execute("INSERT INTO t VALUES (NULL, x'DEADBEEF')")

        let result = try await connection.execute("SELECT a, b FROM t")
        XCTAssertEqual(result[0, 0], .null)
        XCTAssertEqual(result[0, 1], .data(Data([0xDE, 0xAD, 0xBE, 0xEF])))
    }

    func testSQLErrorSurfaced() async throws {
        let connection = makeConnection()
        try await connection.connect(password: nil)
        do {
            _ = try await connection.execute("SELECT * FROM missing_table")
            XCTFail("expected an error")
        } catch let error as SQLDriverError {
            XCTAssertEqual(error, .sqlite(message: "no such table: missing_table"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testStreamingRows() async throws {
        let connection = makeConnection()
        try await connection.connect(password: nil)
        _ = try await connection.execute("CREATE TABLE t (n INTEGER)")
        _ = try await connection.execute("INSERT INTO t VALUES (1), (2), (3), (4), (5)")

        let streamed = try await connection.stream("SELECT n FROM t")
        XCTAssertEqual(streamed.columns.map(\.name), ["n"])

        var collected: [Int64] = []
        for try await row in streamed.rows {
            if case .int(let value) = row.values[0] {
                collected.append(value)
            }
        }
        XCTAssertEqual(collected, [1, 2, 3, 4, 5])
    }

    func testNotConnectedThrows() async {
        let connection = makeConnection()
        do {
            _ = try await connection.execute("SELECT 1")
            XCTFail("expected an error")
        } catch let error as SQLDriverError {
            XCTAssertEqual(error, .connectionFailed(message: "Not connected"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMissingPathThrows() async {
        let connection = SQLiteConnection(profile: ConnectionProfile(name: "x", kind: .sqlite, database: ""))
        do {
            try await connection.connect(password: nil)
            XCTFail("expected an error")
        } catch let error as SQLDriverError {
            XCTAssertEqual(error, .sqlite(message: "No database file path set in the profile"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

extension QueryResult {
    fileprivate subscript(row: Int, column: Int) -> SQLValue {
        guard rows.indices.contains(row), let cols = columns, cols.indices.contains(column) else { return .null }
        let values = rows[row].values
        return values.indices.contains(column) ? values[column] : .null
    }
}
