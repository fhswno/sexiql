import XCTest
@testable import SQLDrivers
import SQLCore

final class SchemaBrowserTests: XCTestCase {
    func testQuoteIdentifiers() {
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("users", kind: .sqlite), "\"users\"")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("a\"b", kind: .postgres), "\"a\"\"b\"")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("users", kind: .mysql), "`users`")
        XCTAssertEqual(SchemaBrowser.quoteIdentifier("a`b", kind: .mysql), "`a``b`")
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

    func testSearchPathSQLQuotesSchemas() {
        let sql = SchemaBrowser.searchPathSQL(schemas: ["public", "app", "public"])
        XCTAssertEqual(sql, "SET search_path TO \"$user\", \"public\", \"app\"")
        XCTAssertNil(SchemaBrowser.searchPathSQL(schemas: []))
    }
}
