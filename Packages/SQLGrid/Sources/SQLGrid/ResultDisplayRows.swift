import Foundation
import SQLDrivers

public struct ResultDisplayRow: Sendable, Equatable, Identifiable {
    public var id: Int
    public var values: [SQLValue]

    public init(id: Int, values: [SQLValue]) {
        self.id = id
        self.values = values
    }

    public func value(at ordinal: Int) -> SQLValue {
        guard ordinal >= 0, ordinal < values.count else { return .null }
        return values[ordinal]
    }
}

public enum ResultDisplayRows: Sendable {
    public static func build(
        model: ResultSetModel,
        filterText: String,
        sortOrdinal: Int?,
        sortAscending: Bool
    ) -> [ResultDisplayRow] {
        var built: [ResultDisplayRow] = []
        built.reserveCapacity(model.rows.count)
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)

        for (index, row) in model.rows.enumerated() {
            if !needle.isEmpty {
                let hit = row.values.contains { value in
                    let text = value == .null ? "NULL" : value.displayString
                    return text.localizedCaseInsensitiveContains(needle)
                }
                if !hit { continue }
            }
            built.append(ResultDisplayRow(id: index, values: row.values))
        }

        if let sortOrdinal {
            built.sort { lhs, rhs in
                let result = compareValues(lhs.value(at: sortOrdinal), rhs.value(at: sortOrdinal))
                if result == .orderedSame { return lhs.id < rhs.id }
                return sortAscending
                    ? result == .orderedAscending
                    : result == .orderedDescending
            }
        }
        return built
    }

    public static func snapshot(
        model: ResultSetModel,
        filterText: String,
        sortOrdinal: Int?,
        sortAscending: Bool
    ) -> (columns: [String], rows: [[SQLValue]]) {
        let columns = model.columns.map(\.name)
        let rows = build(
            model: model,
            filterText: filterText,
            sortOrdinal: sortOrdinal,
            sortAscending: sortAscending
        ).map(\.values)
        return (columns, rows)
    }

    public static func compareValues(_ lhs: SQLValue, _ rhs: SQLValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.null, .null): return .orderedSame
        case (.null, _): return .orderedAscending
        case (_, .null): return .orderedDescending
        case (.int(let a), .int(let b)):
            return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case (.double(let a), .double(let b)):
            return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case (.int(let a), .double(let b)):
            let d = Double(a)
            return d == b ? .orderedSame : (d < b ? .orderedAscending : .orderedDescending)
        case (.double(let a), .int(let b)):
            let d = Double(b)
            return a == d ? .orderedSame : (a < d ? .orderedAscending : .orderedDescending)
        case (.bool(let a), .bool(let b)):
            return a == b ? .orderedSame : (!a && b ? .orderedAscending : .orderedDescending)
        default:
            return lhs.displayString.localizedStandardCompare(rhs.displayString)
        }
    }
}
