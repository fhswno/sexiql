import Foundation
import SQLDrivers

public struct ResultRowSelection: Sendable, Equatable {
    public var selectedIDs: Set<Int>
    public var anchorID: Int?

    public init(selectedIDs: Set<Int> = [], anchorID: Int? = nil) {
        self.selectedIDs = selectedIDs
        self.anchorID = anchorID
    }

    public var isEmpty: Bool { selectedIDs.isEmpty }

    public static func click(
        id: Int,
        command: Bool,
        shift: Bool,
        current: ResultRowSelection,
        displayIDs: [Int]
    ) -> ResultRowSelection {
        if shift {
            let anchor = current.anchorID ?? id
            return ResultRowSelection(
                selectedIDs: rangeIDs(from: anchor, to: id, displayIDs: displayIDs),
                anchorID: anchor
            )
        }
        if command {
            var next = current.selectedIDs
            if next.contains(id) {
                next.remove(id)
            } else {
                next.insert(id)
            }
            return ResultRowSelection(selectedIDs: next, anchorID: id)
        }
        return ResultRowSelection(selectedIDs: [id], anchorID: id)
    }

    public static func gutterDrag(
        from startID: Int,
        to endID: Int,
        displayIDs: [Int]
    ) -> ResultRowSelection {
        ResultRowSelection(
            selectedIDs: rangeIDs(from: startID, to: endID, displayIDs: displayIDs),
            anchorID: startID
        )
    }

    public static func dragEndIndex(
        startDisplayIndex: Int,
        translationHeight: CGFloat,
        rowHeight: CGFloat,
        rowCount: Int
    ) -> Int {
        guard rowCount > 0, rowHeight > 0 else { return 0 }
        let delta = Int((translationHeight / rowHeight).rounded())
        return min(max(startDisplayIndex + delta, 0), rowCount - 1)
    }

    public static func indicesIntersecting(
        minY: CGFloat,
        maxY: CGFloat,
        rowHeight: CGFloat,
        rowCount: Int
    ) -> Range<Int>? {
        guard rowCount > 0, rowHeight > 0 else { return nil }
        let top = min(minY, maxY)
        let bottom = max(minY, maxY)
        let lo = min(max(Int(floor(top / rowHeight)), 0), rowCount - 1)
        let hi = min(max(Int(floor((bottom - 0.001) / rowHeight)), 0), rowCount - 1)
        return lo..<(hi + 1)
    }

    public static func prune(
        _ current: ResultRowSelection,
        visibleIDs: Set<Int>
    ) -> ResultRowSelection {
        let next = current.selectedIDs.intersection(visibleIDs)
        let anchor = current.anchorID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        return ResultRowSelection(selectedIDs: next, anchorID: anchor)
    }

    public static func prepareContextSelection(
        id: Int,
        current: ResultRowSelection
    ) -> ResultRowSelection {
        if current.selectedIDs.contains(id) { return current }
        return ResultRowSelection(selectedIDs: [id], anchorID: id)
    }

    public static func rangeIDs(from startID: Int, to endID: Int, displayIDs: [Int]) -> Set<Int> {
        guard let start = displayIDs.firstIndex(of: startID),
              let end = displayIDs.firstIndex(of: endID) else {
            return [endID]
        }
        let lo = min(start, end)
        let hi = max(start, end)
        return Set(displayIDs[lo...hi])
    }
}

extension ResultDisplayRows {
    public static func selected(
        from displayRows: [ResultDisplayRow],
        ids: Set<Int>
    ) -> [ResultDisplayRow] {
        guard !ids.isEmpty else { return [] }
        return displayRows.filter { ids.contains($0.id) }
    }

    public static func tsv(columns: [String], rows: [[SQLValue]]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append(columns.joined(separator: "\t"))
        for row in rows {
            lines.append(row.map { ResultGridLogic.tsvField($0) }.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    public static func valuesSQL(rows: [[SQLValue]]) -> String {
        guard !rows.isEmpty else { return "" }
        if rows.count == 1 {
            return ResultGridLogic.valuesSQL(fields: rows[0])
        }
        let tuples = rows.map { fields in
            let inner = ResultGridLogic.valuesSQL(fields: fields)
            if inner.hasPrefix("VALUES "), inner.hasSuffix(";") {
                return String(inner.dropFirst("VALUES ".count).dropLast())
            }
            return inner
        }
        return "VALUES\n" + tuples.joined(separator: ",\n") + ";"
    }
}
