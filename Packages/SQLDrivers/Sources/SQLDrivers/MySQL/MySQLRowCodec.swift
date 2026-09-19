import Foundation

enum MySQLRowCodec: Sendable {
    static let maximumTerminatorPayload = 0xFF_FFFF

    static func rowTerminatorStatus(_ payload: Data, deprecateEOF: Bool) -> UInt16? {
        guard let first = payload.first, first == 0xfe, payload.count <= Self.maximumTerminatorPayload else {
            return nil
        }
        if !deprecateEOF {
            guard payload.count >= 5 else { return nil }
            return UInt16(payload[payload.startIndex + 3])
                | (UInt16(payload[payload.startIndex + 4]) << 8)
        }
        var reader = MySQLByteReader(data: payload, offset: 1)
        guard ((try? reader.readLengthEncodedInteger()) ?? nil) != nil,
              ((try? reader.readLengthEncodedInteger()) ?? nil) != nil,
              let status = try? reader.readUInt16() else {
            return nil
        }
        return status
    }

    static func isRowTerminator(_ payload: Data, deprecateEOF: Bool) -> Bool {
        rowTerminatorStatus(payload, deprecateEOF: deprecateEOF) != nil
    }

    static func parseTextRow(_ payload: Data, columns: [SQLColumn]) throws -> SQLRow {
        var reader = MySQLByteReader(data: payload)
        var values: [SQLValue] = []
        values.reserveCapacity(columns.count)
        for column in columns {
            let bytes = try reader.readLengthEncodedBytes()
            values.append(bytes.map { parseTextValue($0, typeName: column.dataType) } ?? .null)
        }
        return SQLRow(values: values)
    }

    static func parseBinaryRow(_ payload: Data, columns: [SQLColumn]) throws -> SQLRow {
        var reader = MySQLByteReader(data: payload)
        guard try reader.readUInt8() == 0x00 else { throw MySQLWireError.invalidPacket }
        let bitmapLength = (columns.count + 7 + 2) / 8
        let nullBitmap = try reader.readBytes(bitmapLength)
        var values: [SQLValue] = []
        values.reserveCapacity(columns.count)
        for (index, column) in columns.enumerated() {
            let bit = index + 2
            if nullBitmap[nullBitmap.startIndex + bit / 8] & (1 << (bit % 8)) != 0 {
                values.append(.null)
                continue
            }
            values.append(try parseBinaryValue(&reader, type: MySQLTypeCode(type: column.dataType), unsigned: false))
        }
        return SQLRow(values: values)
    }

    static func columns(from definitions: [MySQLColumnDefinition]) -> [SQLColumn] {
        definitions.enumerated().map { index, definition in
            SQLColumn(
                name: definition.name,
                dataType: dataType(for: definition),
                isNullable: (definition.flags & 0x0001) == 0,
                ordinal: index,
                tableName: definition.tableName,
                tableSchema: definition.schema
            )
        }
    }

    static func dataType(for definition: MySQLColumnDefinition) -> String {
        if definition.type == MySQLColumnType.tiny, definition.columnLength == 1 {
            return "bool"
        }
        if definition.characterSet != 63, MySQLColumnType.isTextualBlob(definition.type) {
            return "text"
        }
        return displayType(definition.type)
    }

    static func displayType(_ type: UInt8) -> String {
        switch type {
        case MySQLColumnType.tiny: "tiny"
        case MySQLColumnType.short: "short"
        case MySQLColumnType.long: "long"
        case MySQLColumnType.longLong: "longlong"
        case MySQLColumnType.float: "float"
        case MySQLColumnType.double: "double"
        case MySQLColumnType.decimal, MySQLColumnType.newDecimal: "decimal"
        case MySQLColumnType.date: "date"
        case MySQLColumnType.time: "time"
        case MySQLColumnType.timestamp, MySQLColumnType.dateTime: "datetime"
        case MySQLColumnType.json: "json"
        case MySQLColumnType.tinyBlob: "tinyblob"
        case MySQLColumnType.mediumBlob: "mediumblob"
        case MySQLColumnType.longBlob: "longblob"
        case MySQLColumnType.blob: "blob"
        default: "varchar"
        }
    }

    // MARK: - Private

    private static func parseTextValue(_ bytes: Data, typeName: String) -> SQLValue {
        let text = String(data: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
        switch typeName {
        case "tiny", "short", "long", "int24", "longlong", "year":
            return Int64(text).map(SQLValue.int) ?? .string(text)
        case "float", "double":
            return Double(text).map(SQLValue.double) ?? .string(text)
        case "bool":
            switch text.lowercased() {
            case "true", "t", "1": return .bool(true)
            case "false", "f", "0": return .bool(false)
            default: return Int64(text).map(SQLValue.int) ?? .string(text)
            }
        case "blob", "tinyblob", "mediumblob", "longblob":
            return .data(bytes)
        default:
            return .string(text)
        }
    }

    private static func parseBinaryValue(
        _ reader: inout MySQLByteReader,
        type: MySQLTypeCode,
        unsigned: Bool
    ) throws -> SQLValue {
        _ = unsigned
        switch type.raw {
        case MySQLColumnType.tiny:
            return .int(Int64(try reader.readUInt8()))
        case MySQLColumnType.short:
            return .int(Int64(try reader.readUInt16()))
        case MySQLColumnType.long, MySQLColumnType.int24:
            return .int(Int64(try reader.readUInt32()))
        case MySQLColumnType.longLong:
            return .int(Int64(bitPattern: try reader.readUInt64()))
        case MySQLColumnType.float:
            let bits = try reader.readUInt32()
            return .double(Double(Float(bitPattern: bits)))
        case MySQLColumnType.double:
            return .double(Double(bitPattern: try reader.readUInt64()))
        default:
            return .string(try reader.readLengthEncodedString() ?? "")
        }
    }

    private struct MySQLTypeCode {
        let raw: UInt8
        init(type: String) {
            switch type {
            case "tiny": raw = MySQLColumnType.tiny
            case "short": raw = MySQLColumnType.short
            case "long": raw = MySQLColumnType.long
            case "longlong": raw = MySQLColumnType.longLong
            case "float": raw = MySQLColumnType.float
            case "double": raw = MySQLColumnType.double
            default: raw = MySQLColumnType.varString
            }
        }
    }
}
