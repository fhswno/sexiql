import Foundation
import SQLDrivers

public struct GridColumn: Sendable, Equatable, Identifiable {
    public var ordinal: Int
    public var name: String
    public var dataType: String
    public var width: Double?

    public var id: Int { ordinal }

    public init(ordinal: Int, name: String, dataType: String, width: Double? = nil) {
        self.ordinal = ordinal
        self.name = name
        self.dataType = dataType
        self.width = width
    }
}

public struct GridSelection: Sendable, Equatable {
    public var columnOrdinals: Set<Int>
    public var rowIndices: Range<Int>?

    public init(columnOrdinals: Set<Int> = [], rowIndices: Range<Int>? = nil) {
        self.columnOrdinals = columnOrdinals
        self.rowIndices = rowIndices
    }
}

public struct CellKey: Hashable, Sendable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

public struct ResultSetModel: Sendable, Equatable {
    public private(set) var columns: [GridColumn]
    public private(set) var rows: [SQLRow]
    public private(set) var totalRowCount: Int?
    public private(set) var isComplete: Bool
    public private(set) var editedCells: Set<CellKey>

    public init(columns: [GridColumn], rows: [SQLRow] = [], totalRowCount: Int? = nil, isComplete: Bool = false, editedCells: Set<CellKey> = []) {
        self.columns = columns
        self.rows = rows
        self.totalRowCount = totalRowCount
        self.isComplete = isComplete
        self.editedCells = editedCells
    }

    public mutating func append(_ row: SQLRow) {
        guard !isComplete else { return }
        guard row.values.count == columns.count else { return }
        rows.append(row)
    }

    public mutating func append(contentsOf newRows: [SQLRow]) {
        for row in newRows { append(row) }
    }

    public mutating func finish(totalRowCount: Int? = nil) {
        isComplete = true
        self.totalRowCount = totalRowCount ?? rows.count
    }

    public mutating func setValue(_ value: SQLValue, at row: Int, column: Int) {
        guard rows.indices.contains(row), rows[row].values.indices.contains(column) else { return }
        rows[row].values[column] = value
    }

    public mutating func markEdited(row: Int, column: Int) {
        editedCells.insert(CellKey(row: row, column: column))
    }

    public mutating func insertRow(_ row: SQLRow, at index: Int) {
        guard row.values.count == columns.count else { return }
        let i = min(max(index, 0), rows.count)
        rows.insert(row, at: i)
        editedCells = Set(editedCells.map { key in
            key.row >= i ? CellKey(row: key.row + 1, column: key.column) : key
        })
        if let total = totalRowCount {
            totalRowCount = total + 1
        }
    }

    public mutating func removeRow(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        var next = Set<CellKey>()
        for key in editedCells {
            if key.row == index { continue }
            if key.row > index {
                next.insert(CellKey(row: key.row - 1, column: key.column))
            } else {
                next.insert(key)
            }
        }
        editedCells = next
        if let total = totalRowCount {
            totalRowCount = max(0, total - 1)
        }
    }

    public subscript(row: Int, column: Int) -> SQLValue {
        guard rows.indices.contains(row), columns.indices.contains(column) else { return .null }
        let values = rows[row].values
        guard values.indices.contains(column) else { return .null }
        return values[column]
    }
}
