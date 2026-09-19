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

    func testRowTerminatorStatus() {
        XCTAssertEqual(MySQLRowCodec.rowTerminatorStatus(Data([0xfe, 0, 0, 8, 0]), deprecateEOF: false), 8)
        XCTAssertEqual(MySQLRowCodec.rowTerminatorStatus(Data([0xfe, 0, 0, 8, 0]), deprecateEOF: true), 8)
        XCTAssertNil(MySQLRowCodec.rowTerminatorStatus(Data([0xfe, 0, 0]), deprecateEOF: false))
        XCTAssertNil(MySQLRowCodec.rowTerminatorStatus(Data([0xfe, 0, 0]), deprecateEOF: true))
        XCTAssertNil(MySQLRowCodec.rowTerminatorStatus(Data([0x01, 0x41]), deprecateEOF: false))
        XCTAssertNil(MySQLRowCodec.rowTerminatorStatus(Data(), deprecateEOF: false))

        var okWithFeHeader = Data([0xfe])
        okWithFeHeader.append(MySQLWire.lengthEncodedInteger(0))
        okWithFeHeader.append(MySQLWire.lengthEncodedInteger(0))
        okWithFeHeader.append(MySQLWire.uint16(8))
        XCTAssertEqual(MySQLRowCodec.rowTerminatorStatus(okWithFeHeader, deprecateEOF: true), 8)
        XCTAssertTrue(MySQLRowCodec.isRowTerminator(okWithFeHeader, deprecateEOF: true))
        XCTAssertTrue(MySQLRowCodec.isRowTerminator(Data([0xfe, 0, 0, 8, 0]), deprecateEOF: false))
    }

    func testBinaryAndEmptyStringRowsAreNotTerminators() {
        let binaryRow = Data([0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00])
        XCTAssertNil(MySQLRowCodec.rowTerminatorStatus(binaryRow, deprecateEOF: false))
        XCTAssertNil(MySQLRowCodec.rowTerminatorStatus(binaryRow, deprecateEOF: true))
        XCTAssertFalse(MySQLRowCodec.isRowTerminator(binaryRow, deprecateEOF: true))

        let textRowStartingWithEmptyString = Data([0x00, 0x03]) + Data("abc".utf8)
        XCTAssertNil(MySQLRowCodec.rowTerminatorStatus(textRowStartingWithEmptyString, deprecateEOF: true))
    }

    func testColumnsRemapBoolAndTextBlobs() throws {
        func definition(charset: UInt16, length: UInt32, type: UInt8) -> MySQLColumnDefinition {
            var payload = Data()
            payload.append(MySQLWire.lengthEncoded("def"))
            payload.append(MySQLWire.lengthEncoded("db"))
            payload.append(MySQLWire.lengthEncoded("t"))
            payload.append(MySQLWire.lengthEncoded("t"))
            payload.append(MySQLWire.lengthEncoded("c"))
            payload.append(MySQLWire.lengthEncoded("c"))
            payload.append(0x0c)
            payload.append(contentsOf: [UInt8(charset & 0xff), UInt8(charset >> 8)])
            payload.append(contentsOf: [UInt8(length & 0xff), UInt8((length >> 8) & 0xff), UInt8((length >> 16) & 0xff), UInt8((length >> 24) & 0xff)])
            payload.append(type)
            payload.append(contentsOf: [0, 0])
            payload.append(0)
            payload.append(contentsOf: [0, 0])
            return try! MySQLColumnDefinition.parse(payload)
        }

        let boolColumn = MySQLRowCodec.columns(from: [
            definition(charset: 33, length: 1, type: MySQLColumnType.tiny)
        ])
        XCTAssertEqual(boolColumn.first?.dataType, "bool")

        let textBlob = MySQLRowCodec.columns(from: [
            definition(charset: 33, length: 255, type: MySQLColumnType.blob)
        ])
        XCTAssertEqual(textBlob.first?.dataType, "text")

        let binaryBlob = MySQLRowCodec.columns(from: [
            definition(charset: 63, length: 255, type: MySQLColumnType.blob)
        ])
        XCTAssertEqual(binaryBlob.first?.dataType, "blob")
    }

    func testParseTextValueBool() throws {
        let columns = [SQLColumn(name: "b", dataType: "bool", ordinal: 0)]
        XCTAssertEqual(try MySQLRowCodec.parseTextRow(Data([1, 0x31]), columns: columns).values, [.bool(true)])
        XCTAssertEqual(try MySQLRowCodec.parseTextRow(Data([1, 0x30]), columns: columns).values, [.bool(false)])
        XCTAssertEqual(try MySQLRowCodec.parseTextRow(Data([1, 0x32]), columns: columns).values, [.int(2)])
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

    func testColumnDefinitionPrefersOrgTable() throws {
        var payload = Data()
        payload.append(MySQLWire.lengthEncoded("def"))
        payload.append(MySQLWire.lengthEncoded("app"))
        payload.append(MySQLWire.lengthEncoded("u"))
        payload.append(MySQLWire.lengthEncoded("users"))
        payload.append(MySQLWire.lengthEncoded("ident"))
        payload.append(MySQLWire.lengthEncoded("id"))
        payload.append(0x0c)
        payload.append(contentsOf: [0x21, 0x00]) // character set
        payload.append(contentsOf: [0x0b, 0x00, 0x00, 0x00]) // column length
        payload.append(MySQLColumnType.longLong)
        payload.append(contentsOf: [0x00, 0x00]) // flags
        payload.append(0x00) // decimals
        payload.append(contentsOf: [0x00, 0x00]) // filler

        let definition = try MySQLColumnDefinition.parse(payload)
        XCTAssertEqual(definition.name, "ident")
        XCTAssertEqual(definition.tableName, "users")
        XCTAssertEqual(definition.schema, "app")
        XCTAssertEqual(definition.type, MySQLColumnType.longLong)

        let columns = MySQLRowCodec.columns(from: [definition])
        XCTAssertEqual(columns.first?.tableName, "users")
        XCTAssertEqual(columns.first?.tableSchema, "app")
    }

    func testCommandConstants() {
        XCTAssertEqual(MySQLPrepared.comQuery, 0x03)
        XCTAssertEqual(MySQLPrepared.comStmtPrepare, 0x16)
        XCTAssertEqual(MySQLPrepared.comStmtExecute, 0x17)
        XCTAssertEqual(MySQLPrepared.comStmtClose, 0x19)
    }
}
