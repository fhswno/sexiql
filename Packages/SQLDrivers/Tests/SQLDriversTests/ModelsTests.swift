import XCTest
@testable import SQLDrivers
import SQLCore

final class ModelsTests: XCTestCase {
    func testQueryResultClassification() {
        let rows = QueryResult(columns: [SQLColumn(name: "a", dataType: "int4", ordinal: 0)], rows: [SQLRow(values: [.int(1)])])
        XCTAssertTrue(rows.isResultSet)
        let update = QueryResult(affectedRowCount: 3)
        XCTAssertFalse(update.isResultSet)
        XCTAssertEqual(update.affectedRowCount, 3)
    }

    func testSQLValueDisplayStrings() {
        XCTAssertEqual(SQLValue.null.displayString, "NULL")
        XCTAssertEqual(SQLValue.bool(true).displayString, "true")
        XCTAssertEqual(SQLValue.int(-42).displayString, "-42")
        XCTAssertEqual(SQLValue.string("hi").displayString, "hi")
    }

    func testConnectionFactoryMapsKinds() async {
        let factory = ConnectionFactory()
        let pg = factory.makeConnection(for: ConnectionProfile(name: "p", kind: .postgres))
        let my = factory.makeConnection(for: ConnectionProfile(name: "m", kind: .mysql))
        let sq = factory.makeConnection(for: ConnectionProfile(name: "s", kind: .sqlite))
        let rd = factory.makeConnection(for: ConnectionProfile(name: "r", kind: .redis))

        XCTAssertEqual(pg.profile.kind, .postgres)
        XCTAssertEqual(my.profile.kind, .mysql)
        XCTAssertEqual(sq.profile.kind, .sqlite)
        XCTAssertEqual(rd.profile.kind, .redis)

        let connected = await pg.isConnected()
        XCTAssertFalse(connected)
    }

    func testInspectDetectsJSON() {
        XCTAssertEqual(SQLValueInspect.kind(of: .null), .null)
        XCTAssertEqual(SQLValueInspect.kind(of: .string("hello")), .string)
        XCTAssertEqual(SQLValueInspect.kind(of: .string("{\"a\":1}")), .json)
        XCTAssertNil(SQLValueInspect.prettyJSON("not json"))
        XCTAssertTrue(SQLValueInspect.prettyJSON("{\"b\":2,\"a\":1}")?.contains("\"a\"") == true)
    }

    func testInspectHexAndSize() {
        let data = Data([0x0A, 0xFF])
        XCTAssertEqual(SQLValueInspect.hexPreview(data), "0a ff")
        XCTAssertEqual(SQLValueInspect.sizeLabel(.string("ab")), "2 characters")
        XCTAssertEqual(SQLValueInspect.sizeLabel(.null), "empty")
        let long = Data(repeating: 1, count: 300)
        XCTAssertTrue(SQLValueInspect.hexPreview(long).hasSuffix(" …"))
    }
}
