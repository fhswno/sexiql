import Foundation
import SQLDrivers

enum ResultGridLogic: Sendable {
    static func visibleIndices(
        model: ResultSetModel,
        filterText: String,
        sortColumn: Int?,
        sortAscending: Bool
    ) -> [Int] {
        var indices = Array(model.rows.indices)
        if !filterText.isEmpty {
            let needle = filterText
            indices = indices.filter { modelRow in
                model.rows[modelRow].values.contains { value in
                    value == .null
                        ? "NULL".localizedCaseInsensitiveContains(needle)
                        : value.displayString.localizedCaseInsensitiveContains(needle)
                }
            }
        }
        if let sortColumn {
            let ascending = sortAscending
            indices.sort { lhs, rhs in
                let order = compareValues(model[lhs, sortColumn], model[rhs, sortColumn])
                if order == .orderedSame { return lhs < rhs }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }
        return indices
    }

    static func compareValues(_ lhs: SQLValue, _ rhs: SQLValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.null, .null): return .orderedSame
        case (.null, _): return .orderedAscending
        case (_, .null): return .orderedDescending
        case (.int(let a), .int(let b)):
            return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case (.int(let a), .double(let b)):
            let d = Double(a)
            return d == b ? .orderedSame : (d < b ? .orderedAscending : .orderedDescending)
        case (.double(let a), .int(let b)):
            let d = Double(b)
            return a == d ? .orderedSame : (a < d ? .orderedAscending : .orderedDescending)
        case (.double(let a), .double(let b)):
            return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case (.bool(let a), .bool(let b)):
            return a == b ? .orderedSame : (a ? .orderedDescending : .orderedAscending)
        case (.string(let a), .string(let b)):
            return a.localizedStandardCompare(b)
        default:
            return lhs.displayString.localizedStandardCompare(rhs.displayString)
        }
    }

    static func parsedValue(_ text: String) -> SQLValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .string("") }
        switch trimmed.uppercased() {
        case "NULL", "∅": return .null
        default: break
        }
        if ["true", "TRUE", "t", "1"].contains(trimmed) { return .bool(true) }
        if ["false", "FALSE", "f", "0"].contains(trimmed) { return .bool(false) }
        if let integer = Int64(trimmed) { return .int(integer) }
        if let double = Double(trimmed.replacingOccurrences(of: ",", with: ".")) { return .double(double) }
        return .string(text)
    }

    static func tsvField(_ value: SQLValue) -> String {
        value == .null ? "NULL" : value.displayString
    }

    static func valuesSQL(fields: [SQLValue]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(fields.count)
        for value in fields {
            switch value {
            case .null: parts.append("NULL")
            case .int, .double, .bool: parts.append(value.displayString)
            default:
                parts.append("'" + value.displayString.replacingOccurrences(of: "'", with: "''") + "'")
            }
        }
        return "VALUES (" + parts.joined(separator: ", ") + ");"
    }
}
