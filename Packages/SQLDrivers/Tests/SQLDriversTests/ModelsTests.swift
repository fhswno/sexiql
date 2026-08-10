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

        XCTAssertEqual(pg.profile.kind, .postgres)
        XCTAssertEqual(my.profile.kind, .mysql)
        XCTAssertEqual(sq.profile.kind, .sqlite)

        let connected = await pg.isConnected()
        XCTAssertFalse(connected)
    }
}
