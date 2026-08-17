import XCTest
@testable import SQLDrivers
import SQLCore

final class SQLiteParameterizedTests: XCTestCase {
    private var dbPath: String!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteParameterizedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("t.sqlite").path
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func makeConnection() async throws -> SQLiteConnection {
        let connection = SQLiteConnection(profile: ConnectionProfile(name: "t", kind: .sqlite, database: dbPath))
        try await connection.connect(password: nil)
        _ = try await connection.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER, price REAL, active BOOLEAN, payload BLOB)")
        return connection
    }

    func testInsertAndSelectWithParameters() async throws {
        let connection = try await makeConnection()
        let insert = try await connection.execute(
            "INSERT INTO items (name, qty, price, active, payload) VALUES (?, ?, ?, ?, ?)",
            parameters: [
                .string("widget"),
                .int(3),
                .double(9.99),
                .bool(true),
                .data(Data([0x01, 0x02])),
            ]
        )
        XCTAssertEqual(insert.affectedRowCount, 1)

        let result = try await connection.execute("SELECT name, qty, price, active, payload FROM items WHERE name = ?", parameters: [.string("widget")])
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result[0, 0], .string("widget"))
        XCTAssertEqual(result[0, 1], .int(3))
        XCTAssertEqual(result[0, 2], .double(9.99))
        XCTAssertEqual(result[0, 3], .int(1))
        XCTAssertEqual(result[0, 4], .data(Data([0x01, 0x02])))
    }

    func testNullAndIntParameters() async throws {
        let connection = try await makeConnection()
        _ = try await connection.execute(
            "INSERT INTO items (name, qty) VALUES (?, ?)",
            parameters: [.string("nulls"), .null]
        )
        let result = try await connection.execute("SELECT qty FROM items WHERE name = ?", parameters: [.string("nulls")])
        XCTAssertEqual(result[0, 0], .null)
    }

    func testParameterizedStringCannotBreakOut() async throws {
        let connection = try await makeConnection()
        let injection = "evil'; DROP TABLE items; --"
        _ = try await connection.execute(
            "INSERT INTO items (name) VALUES (?)",
            parameters: [.string(injection)]
        )
        let result = try await connection.execute("SELECT name FROM items WHERE name = ?", parameters: [.string(injection)])
        XCTAssertEqual(result.rows.count, 1)
        let stillThere = try await connection.execute("SELECT name FROM items")
        XCTAssertEqual(stillThere.rows.count, 1, "table must still exist — the injection must not have executed")
    }

    func testUnboundParametersAreNull() async throws {
        let connection = try await makeConnection()
        _ = try await connection.execute("INSERT INTO items (name, qty) VALUES (?, ?)", parameters: [.string("missing-qty")])
        let result = try await connection.execute("SELECT qty FROM items WHERE name = ?", parameters: [.string("missing-qty")])
        XCTAssertEqual(result[0, 0], .null)
    }

    func testEmptyResultSetKeepsColumns() async throws {
        let connection = try await makeConnection()
        let result = try await connection.execute("SELECT name, qty FROM items WHERE qty = ?", parameters: [.int(999)])
        XCTAssertEqual(result.columns?.map(\.name), ["name", "qty"])
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertTrue(result.isResultSet)
    }
}

final class EditableTableResolverTests: XCTestCase {
    private var dbPath: String!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditableTableResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("t.sqlite").path
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func makeConnection() async throws -> SQLiteConnection {
        let connection = SQLiteConnection(profile: ConnectionProfile(name: "t", kind: .sqlite, database: dbPath))
        try await connection.connect(password: nil)
        return connection
    }

    func testResolvesSingleTableWithPrimaryKey() async throws {
        let connection = try await makeConnection()
        _ = try await connection.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
        _ = try await connection.execute("INSERT INTO users (name) VALUES ('ada')")
        let result = try await connection.execute("SELECT id, name FROM users")

        let resolver = EditableTableResolver()
        let table = try await resolver.resolve(for: connection, columns: result.columns ?? [])
        XCTAssertEqual(table, EditableTable(name: "users", columns: ["id", "name"], primaryKey: ["id"]))
    }

    func testNoPrimaryKeyColumnNotEditable() async throws {
        let connection = try await makeConnection()
        _ = try await connection.execute("CREATE TABLE logs (entry TEXT)")
        let result = try await connection.execute("SELECT entry FROM logs")
        let resolver = EditableTableResolver()
        let table = try await resolver.resolve(for: connection, columns: result.columns ?? [])
        XCTAssertNil(table, "a table with only an implicit rowid and no PK column must not be editable")
    }

    func testJoinColumnsFromTwoTablesNotEditable() async throws {
        let connection = try await makeConnection()
        _ = try await connection.execute("CREATE TABLE a (id INTEGER PRIMARY KEY, x TEXT)")
        _ = try await connection.execute("CREATE TABLE b (id INTEGER PRIMARY KEY, y TEXT)")
        let result = try await connection.execute("SELECT a.id, b.y FROM a JOIN b ON a.id = b.id")
        let resolver = EditableTableResolver()
        let table = try await resolver.resolve(for: connection, columns: result.columns ?? [])
        XCTAssertNil(table, "joined columns come from two tables — must not be editable")
    }

    func testSingleTableNameIgnoresJoins() {
        let one = [
            SQLColumn(name: "id", dataType: "int", ordinal: 0, tableName: "users"),
            SQLColumn(name: "name", dataType: "text", ordinal: 1, tableName: "users"),
        ]
        XCTAssertEqual(EditableTableResolver.singleTableName(from: one), "users")
        let joined = [
            SQLColumn(name: "id", dataType: "int", ordinal: 0, tableName: "a"),
            SQLColumn(name: "y", dataType: "text", ordinal: 1, tableName: "b"),
        ]
        XCTAssertNil(EditableTableResolver.singleTableName(from: joined))
    }

    func testMySQLUpdateSQLUsesBackticks() {
        let table = EditableTable(name: "users", columns: ["id", "name"], primaryKey: ["id"], schema: "app")
        let sql = CellUpdateSQL.statement(table: table, column: 1, kind: .mysql)
        XCTAssertEqual(sql, "UPDATE `app`.`users` SET `name` = ? WHERE `id` = ?")
    }

    func testDeleteAndInsertSQL() {
        let table = EditableTable(name: "users", columns: ["id", "name"], primaryKey: ["id"], schema: "app")
        XCTAssertEqual(
            CellDeleteSQL.statement(table: table, kind: .mysql),
            "DELETE FROM `app`.`users` WHERE `id` = ?"
        )
        XCTAssertEqual(
            CellInsertSQL.defaultValues(table: table, kind: .postgres),
            "INSERT INTO \"app\".\"users\" DEFAULT VALUES RETURNING *"
        )
        XCTAssertEqual(
            CellInsertSQL.defaultValues(table: table, kind: .mysql),
            "INSERT INTO `app`.`users` () VALUES ()"
        )
        XCTAssertEqual(
            CellInsertSQL.explicit(table: table, columnNames: ["id", "name"], kind: .sqlite),
            "INSERT INTO \"app\".\"users\" (\"id\", \"name\") VALUES (?, ?) RETURNING *"
        )
    }

    func testDraftMissingRequiredSkipsPrimaryKey() {
        let columns = [
            SQLColumn(name: "id", dataType: "int", isNullable: false, ordinal: 0),
            SQLColumn(name: "company_name", dataType: "text", isNullable: false, ordinal: 1),
            SQLColumn(name: "note", dataType: "text", isNullable: true, ordinal: 2),
        ]
        let missing = DraftRowRequirements.missing(
            columns: columns,
            values: [.null, .null, .null],
            primaryKey: ["id"]
        )
        XCTAssertEqual(missing, ["company_name"])
        let ready = DraftRowRequirements.missing(
            columns: columns,
            values: [.null, .string("Acme"), .null],
            primaryKey: ["id"]
        )
        XCTAssertTrue(ready.isEmpty)
    }

    func testMutationRowIndexShift() {
        XCTAssertEqual(MutationRowIndex.afterDelete(5, deleted: 2), 4)
        XCTAssertNil(MutationRowIndex.afterDelete(2, deleted: 2))
        XCTAssertEqual(MutationRowIndex.afterInsert(2, inserted: 2), 3)
        XCTAssertEqual(MutationRowIndex.afterInsert(1, inserted: 2), 1)
    }

    func testPostgresUpdateSQLUnchanged() {
        let table = EditableTable(name: "users", columns: ["id", "name"], primaryKey: ["id"])
        let sql = CellUpdateSQL.statement(table: table, column: 1, kind: .postgres)
        XCTAssertEqual(sql, "UPDATE \"users\" SET \"name\" = $1 WHERE \"id\" = $2")
    }

    func testCompositePrimaryKey() async throws {
        let connection = try await makeConnection()
        _ = try await connection.execute("CREATE TABLE t (k1 INTEGER, k2 INTEGER, v TEXT, PRIMARY KEY (k1, k2))")
        let result = try await connection.execute("SELECT k1, k2, v FROM t")
        let resolver = EditableTableResolver()
        let table = try await resolver.resolve(for: connection, columns: result.columns ?? [])
        XCTAssertEqual(table?.primaryKey, ["k1", "k2"])
    }
}

extension QueryResult {
    fileprivate subscript(row: Int, column: Int) -> SQLValue {
        guard rows.indices.contains(row), let cols = columns, cols.indices.contains(column) else { return .null }
        let values = rows[row].values
        return values.indices.contains(column) ? values[column] : .null
    }
}
