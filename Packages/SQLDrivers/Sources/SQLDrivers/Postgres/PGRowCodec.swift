import Foundation

enum PGRowCodec: Sendable {
    static func parseRowDescription(_ payload: Data) throws -> [SQLColumn] {
        var reader = PGByteReader(data: payload)
        let count = Int(try reader.readInt16())
        guard count >= 0 else { throw PGWireError.invalidMessage }
        var columns: [SQLColumn] = []
        columns.reserveCapacity(count)
        for index in 0..<count {
            let name = try reader.readCString()
            let tableOID = try reader.readUInt32()
            _ = try reader.readInt16()
            let typeOID = try reader.readUInt32()
            _ = try reader.readInt16()
            _ = try reader.readInt32()
            _ = try reader.readInt16()
            columns.append(SQLColumn(
                name: name,
                dataType: PGTypeID(rawValue: typeOID)?.displayName ?? "oid:\(typeOID)",
                isNullable: true,
                ordinal: index,
                tableOID: tableOID
            ))
        }
        return columns
    }

    static func parseDataRow(_ payload: Data, columns: [SQLColumn]) throws -> SQLRow {
        var reader = PGByteReader(data: payload)
        let count = Int(try reader.readInt16())
        guard count == columns.count else { throw PGWireError.invalidMessage }
        var values: [SQLValue] = []
        values.reserveCapacity(count)
        for column in columns {
            let length = try reader.readInt32()
            if length == -1 {
                values.append(.null)
            } else if length < 0 {
                throw PGWireError.invalidMessage
            } else {
                let bytes = try reader.readBytes(Int(length))
                let text = try readerString(bytes)
                values.append(parsePGValue(text: text, oid: oid(for: column.dataType)))
            }
        }
        return SQLRow(values: values)
    }

    static func parseCommandTag(_ payload: Data) -> String? {
        let tag = String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .newlines)
        return tag.isEmpty ? nil : tag
    }

    static func affectedRows(from tag: String?) -> Int? {
        guard let tag else { return nil }
        let parts = tag.split(separator: " ")
        if let last = parts.last, let value = Int(last) {
            return value
        }
        return nil
    }

    static func parseErrorResponse(_ payload: Data) throws -> PGError {
        var reader = PGByteReader(data: payload)
        var code = ""
        var message = ""
        var detail: String?
        var hint: String?
        var position: Int?
        while !reader.isAtEnd {
            let field = try reader.readInt8()
            if field == 0 { break }
            let value = try reader.readCString()
            switch field {
            case 0x43: code = value
            case 0x4D: message = value
            case 0x44: detail = value
            case 0x48: hint = value
            case 0x50: position = Int(value)
            default: continue
            }
        }
        return PGError(
            code: code,
            message: message.isEmpty ? "Database error" : message,
            detail: detail,
            hint: hint,
            position: position
        )
    }

    static func textEncoding(_ value: SQLValue) -> String {
        switch value {
        case .null:
            ""
        case .bool(let flag):
            flag ? "t" : "f"
        case .int(let integer):
            String(integer)
        case .double(let double):
            String(double)
        case .string(let string):
            string
        case .data(let data):
            "\\x" + data.map { String(format: "%02x", $0) }.joined()
        case .date(let date):
            dateFormatter.string(from: date)
        }
    }

    static func readSASLMechanisms(reader: PGByteReader) throws -> [String] {
        var mechanisms: [String] = []
        var reader = reader
        while !reader.isAtEnd {
            let mechanism = try reader.readCString()
            if mechanism.isEmpty { break }
            mechanisms.append(mechanism)
        }
        return mechanisms
    }

    // MARK: - Private

    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func oid(for dataType: String) -> UInt32 {
        PGTypeID.allCases.first { $0.displayName == dataType }?.rawValue ?? 0
    }

    private static func readerString(_ bytes: Data) throws -> String {
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw PGWireError.invalidUTF8
        }
        return string
    }
}
