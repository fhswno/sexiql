import XCTest
@testable import SQLDrivers
import SQLCore

final class MySQLCodecTests: XCTestCase {
    func testDisplayTypeMapping() {
        XCTAssertEqual(MySQLRowCodec.displayType(MySQLColumnType.longLong), "longlong")
        XCTAssertEqual(MySQLRowCodec.displayType(MySQLColumnType.varString), "varchar")
        XCTAssertEqual(MySQLRowCodec.displayType(MySQLColumnType.json), "json")
    }

    func testParseTextRow() throws {
        let columns = [
            SQLColumn(name: "id", dataType: "longlong", isNullable: false, ordinal: 0),
            SQLColumn(name: "name", dataType: "varchar", isNullable: true, ordinal: 1),
        ]
        var payload = Data()
        payload.append(MySQLWire.lengthEncoded(Data("42".utf8)))
        payload.append(MySQLWire.lengthEncoded(Data("ada".utf8)))
        let row = try MySQLRowCodec.parseTextRow(payload, columns: columns)
        XCTAssertEqual(row.values, [.int(42), .string("ada")])
    }

    func testParseTextRowNull() throws {
        let columns = [
            SQLColumn(name: "n", dataType: "varchar", isNullable: true, ordinal: 0),
        ]
        var payload = Data()
        payload.append(0xfb)
        let row = try MySQLRowCodec.parseTextRow(payload, columns: columns)
        XCTAssertEqual(row.values, [.null])
    }

    func testIsTerminator() {
        XCTAssertTrue(MySQLRowCodec.isTerminator(Data()))
        XCTAssertTrue(MySQLRowCodec.isTerminator(Data([0xfe, 0, 0, 2, 0])))
        XCTAssertFalse(MySQLRowCodec.isTerminator(Data([0x01, 0x41])))
    }

    func testBuildExecutePayloadNullBitmapAndInt() {
        let payload = MySQLPrepared.buildExecutePayload(
            statementID: 7,
            parameters: [.null, .int(99)]
        )
        XCTAssertEqual(payload[payload.startIndex..<payload.startIndex + 4], MySQLWire.uint32(7)[...])
        XCTAssertEqual(payload[payload.startIndex + 4], 0)
        let bitmapIndex = payload.startIndex + 9
        XCTAssertEqual(payload[bitmapIndex] & 0x01, 0x01)
        XCTAssertEqual(payload[bitmapIndex] & 0x02, 0)
    }

    func testCommandConstants() {
        XCTAssertEqual(MySQLPrepared.comQuery, 0x03)
        XCTAssertEqual(MySQLPrepared.comStmtPrepare, 0x16)
        XCTAssertEqual(MySQLPrepared.comStmtExecute, 0x17)
        XCTAssertEqual(MySQLPrepared.comStmtClose, 0x19)
    }
}
