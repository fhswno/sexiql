import XCTest
@testable import SQLDrivers
import SQLCore

final class SchemaBrowserTests: XCTestCase {
    func testQuoteIdentifiers() {
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("users", kind: .sqlite), "\"users\"")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("a\"b", kind: .postgres), "\"a\"\"b\"")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("users", kind: .mysql), "`users`")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("a`b", kind: .mysql), "`a``b`")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("plain", kind: .redis), "plain")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("has space", kind: .redis), "\"has space\"")
    }

    func testQualify() {
        let plain = SchemaObject(schema: nil, name: "t", kind: .table)
        XCTAssertEqual(SchemaBrowser.qualify(plain, kind: .sqlite), "\"t\"")
        let qualified = SchemaObject(schema: "public", name: "users", kind: .table)
        XCTAssertEqual(SchemaBrowser.qualify(qualified, kind: .postgres), "\"public\".\"users\"")
        XCTAssertEqual(SchemaBrowser.qualify(qualified, kind: .mysql), "`public`.`users`")
    }

    func testSelectAllSQL() {
        let obj = SchemaObject(schema: "public", name: "t", kind: .table)
        XCTAssertEqual(
            SchemaBrowser.selectAllSQL(obj, kind: .postgres, limit: 1000),
            "SELECT * FROM \"public\".\"t\" LIMIT 1000;"
        )
        let key = SchemaObject(schema: "hash", name: "user:1", kind: .key)
        XCTAssertEqual(SchemaBrowser.selectAllSQL(key, kind: .redis), "HGETALL user:1")
        XCTAssertEqual(
            SchemaBrowser.selectAllSQL(obj, kind: .postgres, limit: nil),
            "SELECT * FROM \"public\".\"t\";"
        )
    }

    func testListDatabasesSQL() {
        XCTAssertTrue(SchemaBrowser.listDatabasesSQL(kind: .postgres)?.contains("pg_database") == true)
        XCTAssertEqual(SchemaBrowser.listDatabasesSQL(kind: .mysql), "SHOW DATABASES")
        XCTAssertNil(SchemaBrowser.listDatabasesSQL(kind: .sqlite))
        XCTAssertNil(SchemaBrowser.listDatabasesSQL(kind: .redis))
    }

    func testDatabasesFromResult() {
        let result = QueryResult(
            columns: [SQLColumn(name: "datname", dataType: "text", ordinal: 0)],
            rows: [
                SQLRow(values: [.string("customer_app")]),
                SQLRow(values: [.string("postgres")]),
                SQLRow(values: [.null]),
            ]
        )
        XCTAssertEqual(SchemaBrowser.databases(from: result), ["customer_app", "postgres"])
    }

    func testCancelRequestPacket() {
        let packet = PGWire.cancelRequest(processID: 42, secretKey: 99)
        XCTAssertEqual(packet.count, 16)
    }

    func testParsesPostgresSchemaRows() {
        let rows = [
            SQLRow(values: [.string("app"), .string("s3_iam_connections"), .string("BASE TABLE")]),
            SQLRow(values: [.string("public"), .string("users"), .string("VIEW")]),
        ]
        let objects = SchemaBrowser.objects(
            from: QueryResult(columns: [], rows: rows),
            kind: .postgres
        )
        XCTAssertEqual(objects.map(\.displayName), ["app.s3_iam_connections", "public.users"])
        XCTAssertEqual(objects[0].kind, .table)
        XCTAssertEqual(objects[1].kind, .view)
    }

    func testParsesPostgresIndexesAndForeignKeys() {
        let indexRows = [
            SQLRow(values: [.string("users_pkey"), .bool(true), .bool(true), .string("id")]),
            SQLRow(values: [.string("users_email_key"), .bool(true), .bool(false), .string("email")]),
        ]
        let indexes = SchemaBrowser.indexes(fromPostgresRows: indexRows)
        XCTAssertEqual(indexes.count, 2)
        XCTAssertTrue(indexes[0].isPrimary)
        XCTAssertEqual(indexes[1].detail, "UNIQUE (email)")

        let fkRows = [
            SQLRow(values: [.string("orders_user_fk"), .string("user_id"), .string("public"), .string("users"), .string("id")]),
        ]
        let keys = SchemaBrowser.foreignKeys(fromPostgresRows: fkRows)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].detail, "user_id → public.users.id")
    }

    func testParsesSQLiteForeignKeys() {
        let rows = [
            SQLRow(values: [.int(0), .int(0), .string("users"), .string("user_id"), .string("id")]),
            SQLRow(values: [.int(0), .int(1), .string("users"), .string("org_id"), .string("org_id")]),
        ]
        let keys = SchemaBrowser.foreignKeys(fromSQLiteRows: rows)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].columns, ["user_id", "org_id"])
        XCTAssertEqual(keys[0].refTable, "users")
        XCTAssertEqual(keys[0].refColumns, ["id", "org_id"])
    }

    func testParsesMySQLIndexes() {
        let rows = [
            SQLRow(values: [.string("PRIMARY"), .int(0), .string("id")]),
            SQLRow(values: [.string("idx_name"), .int(1), .string("name")]),
        ]
        let indexes = SchemaBrowser.indexes(fromMySQLRows: rows)
        XCTAssertTrue(indexes[0].isPrimary && indexes[0].isUnique)
        XCTAssertEqual(indexes[1].detail, "INDEX (name)")
    }

    func testSynthesizesPrimaryWhenMissing() {
        let columns = [
            SchemaColumn(name: "id", dataType: "INTEGER", isPrimaryKey: true, isNullable: false),
            SchemaColumn(name: "name", dataType: "TEXT", isPrimaryKey: false, isNullable: false),
        ]
        let added = SchemaBrowser.ensuringPrimaryIndex([], columns: columns)
        XCTAssertEqual(added.count, 1)
        XCTAssertTrue(added[0].isPrimary)
        XCTAssertEqual(added[0].detail, "PRIMARY (id)")

        let existing = [
            SchemaIndex(name: "users_pkey", columns: ["id"], isUnique: true, isPrimary: true),
        ]
        let kept = SchemaBrowser.ensuringPrimaryIndex(existing, columns: columns)
        XCTAssertEqual(kept.map(\.name), ["users_pkey"])
    }

    func testSearchPathSQLQuotesSchemas() {
        let sql = SchemaBrowser.searchPathSQL(schemas: ["public", "app", "public"])
        XCTAssertEqual(sql, "SET search_path TO \"$user\", \"public\", \"app\"")
        XCTAssertNil(SchemaBrowser.searchPathSQL(schemas: []))
    }
}
