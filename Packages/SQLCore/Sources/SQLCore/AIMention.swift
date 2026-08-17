import Foundation

public struct AIMentionToken: Sendable, Equatable {
    public var schema: String?
    public var name: String
    public var utf16Range: Range<Int>

    public init(schema: String?, name: String, utf16Range: Range<Int>) {
        self.schema = schema
        self.name = name
        self.utf16Range = utf16Range
    }

    public var raw: String {
        if let schema, !schema.isEmpty { return "\(schema).\(name)" }
        return name
    }

    public var filterPrefix: String {
        if let schema, !schema.isEmpty {
            return name.isEmpty ? "\(schema)." : "\(schema).\(name)"
        }
        return name
    }
}

public struct AIMentionColumn: Sendable, Equatable {
    public var name: String
    public var dataType: String
    public var isPrimaryKey: Bool
    public var isNullable: Bool

    public init(name: String, dataType: String, isPrimaryKey: Bool, isNullable: Bool) {
        self.name = name
        self.dataType = dataType
        self.isPrimaryKey = isPrimaryKey
        self.isNullable = isNullable
    }
}

public struct AIMentionTable: Sendable, Equatable {
    public var displayName: String
    public var columns: [AIMentionColumn]

    public init(displayName: String, columns: [AIMentionColumn]) {
        self.displayName = displayName
        self.columns = columns
    }
}

public enum AIMention: Sendable {
    public static func tokens(in text: String) -> [AIMentionToken] {
        let units = Array(text.utf16)
        var result: [AIMentionToken] = []
        var i = 0
        while i < units.count {
            if units[i] == 0x40, !isIdentChar(preceding: i, in: units) {
                let start = i
                i += 1
                let bodyStart = i
                while i < units.count, isIdentChar(units[i]) { i += 1 }
                if i < units.count, units[i] == 0x2E {
                    i += 1
                    while i < units.count, isIdentChar(units[i]) { i += 1 }
                }
                if i > bodyStart, let token = makeToken(units: units, start: start, end: i) {
                    result.append(token)
                }
                continue
            }
            i += 1
        }
        return result
    }

    public static func tokenAtCaret(in text: String, utf16Offset: Int) -> AIMentionToken? {
        let units = Array(text.utf16)
        let caret = min(max(utf16Offset, 0), units.count)
        var i = caret
        while i > 0 {
            let prev = units[i - 1]
            if prev == 0x40 {
                if isIdentChar(preceding: i - 1, in: units) { return nil }
                return makeToken(units: units, start: i - 1, end: caret)
            }
            if isIdentChar(prev) || prev == 0x2E {
                i -= 1
                continue
            }
            return nil
        }
        return nil
    }

    public static func formatTables(_ tables: [AIMentionTable], limit: Int = 12) -> String {
        if tables.isEmpty { return "Mentioned tables: (none matched)" }
        var lines = ["Mentioned tables:"]
        for table in tables.prefix(limit) {
            lines.append("- \(table.displayName)")
            if table.columns.isEmpty {
                lines.append("  (columns not loaded)")
            } else {
                for column in table.columns.prefix(80) {
                    lines.append("  \(formatColumn(column))")
                }
            }
        }
        if tables.count > limit {
            lines.append("…and \(tables.count - limit) more")
        }
        return lines.joined(separator: "\n")
    }

    public static func matchRank(query: String, name: String, qualified: String, schema: String?) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = name.lowercased()
        let qualified = qualified.lowercased()
        let schema = schema?.lowercased() ?? ""
        if q.isEmpty { return 50 }
        if name == q || qualified == q { return 0 }
        if name.hasPrefix(q) { return 1 }
        if qualified.hasPrefix(q) || schema.hasPrefix(q) { return 2 }
        if name.contains(q) || qualified.contains(q) || schema.contains(q) { return 3 }
        if fuzzyContains(name, q) || fuzzyContains(qualified, q) { return 4 }
        return nil
    }

    public static func formatColumn(_ column: AIMentionColumn) -> String {
        var parts = [column.name]
        if !column.dataType.isEmpty { parts.append(column.dataType) }
        if column.isPrimaryKey { parts.append("PK") }
        parts.append(column.isNullable ? "NULL" : "NOT NULL")
        return parts.joined(separator: " ")
    }

    private static func makeToken(units: [UInt16], start: Int, end: Int) -> AIMentionToken? {
        guard start < end, units[start] == 0x40 else { return nil }
        let body = String(utf16CodeUnits: Array(units[(start + 1)..<end]), count: end - start - 1)
        let schema: String?
        let name: String
        if let dot = body.firstIndex(of: ".") {
            schema = String(body[..<dot])
            name = String(body[body.index(after: dot)...])
        } else {
            schema = nil
            name = body
        }
        return AIMentionToken(schema: schema, name: name, utf16Range: start..<end)
    }

    private static func fuzzyContains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var index = haystack.startIndex
        for character in needle {
            var found = false
            while index < haystack.endIndex {
                let current = haystack[index]
                haystack.formIndex(after: &index)
                if current == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }

    private static func isIdentChar(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A)
            || (unit >= 0x61 && unit <= 0x7A)
            || (unit >= 0x30 && unit <= 0x39)
            || unit == 0x5F
    }

    private static func isIdentChar(preceding index: Int, in units: [UInt16]) -> Bool {
        guard index > 0 else { return false }
        return isIdentChar(units[index - 1])
    }
}
