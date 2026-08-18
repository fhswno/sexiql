import Foundation
import SQLDrivers

public enum ImportExportError: Error, Sendable, Equatable {
    case malformedCSV(line: Int, message: String)
    case malformedJSON(message: String)
    case emptyFile
}

public enum CSVTextEncoding: String, Sendable, CaseIterable, Identifiable, Equatable {
    case utf8
    case utf16
    case windows1252
    case isoLatin1

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf16: "UTF-16"
        case .windows1252: "Windows-1252"
        case .isoLatin1: "ISO-8859-1"
        }
    }

    public var encoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .utf16: .utf16
        case .windows1252: .windowsCP1252
        case .isoLatin1: .isoLatin1
        }
    }

    public static func from(_ encoding: String.Encoding) -> CSVTextEncoding {
        switch encoding {
        case .utf16, .utf16BigEndian, .utf16LittleEndian: .utf16
        case .windowsCP1252: .windows1252
        case .isoLatin1: .isoLatin1
        default: .utf8
        }
    }
}

public enum CSVDelimiterKind: String, Sendable, CaseIterable, Identifiable, Equatable {
    case comma
    case semicolon
    case tab
    case pipe

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .comma: "Comma"
        case .semicolon: "Semicolon"
        case .tab: "Tab"
        case .pipe: "Pipe"
        }
    }

    public var character: Character {
        switch self {
        case .comma: ","
        case .semicolon: ";"
        case .tab: "\t"
        case .pipe: "|"
        }
    }

    public static func from(_ character: Character) -> CSVDelimiterKind {
        switch character {
        case ";": .semicolon
        case "\t": .tab
        case "|": .pipe
        default: .comma
        }
    }
}

public struct CSVDialect: Sendable, Equatable {
    public var delimiter: Character
    public var quote: Character
    public var encoding: String.Encoding

    public static let csv = CSVDialect(delimiter: ",", quote: "\"", encoding: .utf8)
    public static let tsv = CSVDialect(delimiter: "\t", quote: "\"", encoding: .utf8)

    public init(delimiter: Character = ",", quote: Character = "\"", encoding: String.Encoding = .utf8) {
        self.delimiter = delimiter
        self.quote = quote
        self.encoding = encoding
    }
}

public enum CSVCodec: Sendable {
    public static func encode(columns: [String], rows: [[SQLValue]]) -> String {
        var lines: [String] = []
        lines.append(columns.map(escape).joined(separator: ","))
        for row in rows {
            lines.append(row.map { escape(value: $0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + (lines.isEmpty ? "" : "\r\n")
    }

    public static func parse(_ text: String) throws -> [[String]] {
        try parse(text, dialect: .csv)
    }

    public static func parse(_ text: String, dialect: CSVDialect) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1

        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        let delimiter = dialect.delimiter.unicodeScalars.first ?? ","
        let quote = dialect.quote.unicodeScalars.first ?? "\""

        func finishField() throws {
            row.append(field)
            field = ""
        }

        func finishRow() throws {
            try finishField()
            rows.append(row)
            row = []
        }

        while index < scalars.endIndex {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == quote {
                    let next = scalars.index(after: index)
                    if next < scalars.endIndex, scalars[next] == quote {
                        field.unicodeScalars.append(quote)
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    if scalar == "\n" { line += 1 }
                    field.unicodeScalars.append(scalar)
                }
            } else if scalar == quote {
                guard field.isEmpty else {
                    throw ImportExportError.malformedCSV(line: line, message: "quote inside unquoted field")
                }
                inQuotes = true
            } else if scalar == delimiter {
                try finishField()
            } else if scalar == "\r" {
                // ignore
            } else if scalar == "\n" {
                try finishRow()
                line += 1
            } else {
                field.unicodeScalars.append(scalar)
            }
            index = scalars.index(after: index)
        }
        if inQuotes {
            throw ImportExportError.malformedCSV(line: line, message: "unterminated quoted field")
        }
        if !field.isEmpty || !row.isEmpty {
            try finishRow()
        }
        return rows
    }

    public static func decode(_ data: Data, encoding: String.Encoding) -> String? {
        if encoding == .utf8, data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        return String(data: data, encoding: encoding)
    }

    public static func sniff(_ data: Data) -> CSVDialect {
        let encoding = sniffEncoding(data)
        let text = decode(data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        return CSVDialect(delimiter: sniffDelimiter(in: text), quote: "\"", encoding: encoding)
    }

    public static func sniffEncoding(_ data: Data) -> String.Encoding {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return .utf16 }
        if String(data: data, encoding: .utf8) != nil { return .utf8 }
        if String(data: data, encoding: .windowsCP1252) != nil { return .windowsCP1252 }
        return .isoLatin1
    }

    public static func sniffDelimiter(in text: String) -> Character {
        let sample = text.split(whereSeparator: \.isNewline).prefix(8).joined(separator: "\n")
        let candidates: [Character] = [",", ";", "\t", "|"]
        var best: Character = ","
        var bestCount = -1
        for candidate in candidates {
            let count = unquotedCount(of: candidate, in: sample)
            if count > bestCount {
                best = candidate
                bestCount = count
            }
        }
        return bestCount > 0 ? best : ","
    }

    private static func unquotedCount(of delimiter: Character, in text: String) -> Int {
        var count = 0
        var inQuotes = false
        let quote: Character = "\""
        for character in text {
            if character == quote {
                inQuotes.toggle()
            } else if !inQuotes, character == delimiter {
                count += 1
            }
        }
        return count
    }

    private static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func escape(value: SQLValue) -> String {
        switch value {
        case .null:
            ""
        case .data(let data):
            escape(data.base64EncodedString())
        default:
            escape(value.displayString)
        }
    }
}

public enum JSONCodec: Sendable {
    public static func encode(columns: [String], rows: [[SQLValue]]) throws -> String {
        var objects: [[String: Any]] = []
        objects.reserveCapacity(rows.count)
        for row in rows {
            var object: [String: Any] = [:]
            for (index, column) in columns.enumerated() where index < row.count {
                object[column] = jsonValue(row[index])
            }
            objects.append(object)
        }
        let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw ImportExportError.malformedJSON(message: "encoding failed")
        }
        return string
    }

    public static func parse(_ data: Data) throws -> (columns: [String], rows: [[SQLValue]]) {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ImportExportError.malformedJSON(message: error.localizedDescription)
        }
        guard let array = object as? [[String: Any]] else {
            throw ImportExportError.malformedJSON(message: "expected a JSON array of objects")
        }
        var seen = Set<String>()
        for entry in array {
            for key in entry.keys { seen.insert(key) }
        }
        let columns = seen.sorted()
        let rows: [[SQLValue]] = array.map { entry in
            columns.map { key in
                guard let value = entry[key] else { return .null }
                return sqlValue(from: value)
            }
        }
        return (columns, rows)
    }

    private static func jsonValue(_ value: SQLValue) -> Any {
        switch value {
        case .null: NSNull()
        case .bool(let flag): flag
        case .int(let integer): integer
        case .double(let double): double
        case .string(let string): string
        case .data(let data): data.base64EncodedString()
        case .date(let date): ISO8601DateFormatter().string(from: date)
        }
    }

    private static func sqlValue(from value: Any) -> SQLValue {
        if value is NSNull { return .null }
        if let string = value as? String { return inferredValue(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            switch CFNumberGetType(number) {
            case .floatType, .float32Type, .float64Type, .doubleType, .cgFloatType:
                return .double(number.doubleValue)
            default:
                return .int(number.int64Value)
            }
        }
        return .string(String(describing: value))
    }

    public static func inferredValue(_ text: String) -> SQLValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .string("") }
        switch trimmed.uppercased() {
        case "NULL", "∅": return .null
        default: break
        }
        if let integer = Int64(trimmed) { return .int(integer) }
        if let double = Double(trimmed.replacingOccurrences(of: ",", with: ".")) { return .double(double) }
        return .string(text)
    }
}
