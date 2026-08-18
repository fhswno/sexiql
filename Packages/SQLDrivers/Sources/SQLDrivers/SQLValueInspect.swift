import Foundation

public enum SQLValueInspect: Sendable {
    public enum Kind: String, Sendable, Equatable {
        case null
        case bool
        case int
        case double
        case string
        case json
        case data
        case date

        public var displayName: String {
            switch self {
            case .null: "NULL"
            case .bool: "boolean"
            case .int: "integer"
            case .double: "number"
            case .string: "text"
            case .json: "json"
            case .data: "binary"
            case .date: "date"
            }
        }
    }

    public static func kind(of value: SQLValue) -> Kind {
        switch value {
        case .null: .null
        case .bool: .bool
        case .int: .int
        case .double: .double
        case .date: .date
        case .data: .data
        case .string(let text):
            prettyJSON(text) == nil ? .string : .json
        }
    }

    public static func prettyJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else { return nil }
        return string
    }

    public static func hexPreview(_ data: Data, limit: Int = 256) -> String {
        let slice = data.prefix(limit)
        let hex = slice.map { String(format: "%02x", $0) }.joined(separator: " ")
        if data.count > limit {
            return hex + " …"
        }
        return hex
    }

    public static func sizeLabel(_ value: SQLValue) -> String {
        switch value {
        case .null:
            "empty"
        case .string(let text):
            "\(text.count) character\(text.count == 1 ? "" : "s")"
        case .data(let data):
            "\(data.count) byte\(data.count == 1 ? "" : "s")"
        case .bool, .int, .double, .date:
            kind(of: value).displayName
        }
    }
}
