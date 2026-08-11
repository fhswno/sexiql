import Foundation
import SQLDrivers

public enum ImportExportError: Error, Sendable, Equatable {
    case malformedCSV(line: Int, message: String)
    case malformedJSON(message: String)
    case emptyFile
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
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1

        let scalars = text.unicodeScalars
        var index = scalars.startIndex

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
                if scalar == "\"" {
                    let next = scalars.index(after: index)
                    if next < scalars.endIndex, scalars[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    if scalar == "\n" { line += 1 }
                    field.unicodeScalars.append(scalar)
                }
            } else {
                switch scalar {
                case "\"":
                    guard field.isEmpty else {
                        throw ImportExportError.malformedCSV(line: line, message: "quote inside unquoted field")
                    }
                    inQuotes = true
                case ",":
                    try finishField()
                case "\r":
                    break
                case "\n":
                    try finishRow()
                    line += 1
                default:
                    field.unicodeScalars.append(scalar)
                }
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
