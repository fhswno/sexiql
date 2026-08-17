import Foundation
import SQLDrivers
import SQLGrid

@MainActor
@Observable
final class StatementResult: Identifiable {
    enum Status: Equatable {
        case pending
        case running
        case streaming
        case complete
        case failed
        case cancelled
    }

    let id = UUID()
    let label: String
    var status: Status = .pending
    var model = ResultSetModel(columns: [])
    var message: String?
    var duration: TimeInterval?
    var sqlColumns: [SQLColumn] = []
    var editableTable: EditableTable?
    var isResolvingEditable = false
    var undoStack: [ResultMutation] = []
    var redoStack: [ResultMutation] = []
    var filterText = ""
    var appliedLimit: Int?
    var draftRowIndex: Int?

    init(label: String) {
        self.label = label
    }
}

struct CellEdit: Sendable {
    let table: EditableTable
    let row: Int
    let column: Int
    let oldValue: SQLValue
    let newValue: SQLValue
    let primaryKeyValues: [SQLValue]
}

struct RowMutation: Sendable {
    let table: EditableTable
    let row: Int
    let values: [SQLValue]
    let primaryKeyValues: [SQLValue]
}

enum ResultMutation: Sendable {
    case cell(CellEdit)
    case insert(RowMutation)
    case delete(RowMutation)

    var row: Int {
        switch self {
        case .cell(let edit): edit.row
        case .insert(let mutation), .delete(let mutation): mutation.row
        }
    }

    func shifting(deletedRow: Int) -> ResultMutation? {
        switch self {
        case .cell(let edit):
            guard let next = MutationRowIndex.afterDelete(edit.row, deleted: deletedRow) else { return nil }
            return .cell(
                CellEdit(
                    table: edit.table,
                    row: next,
                    column: edit.column,
                    oldValue: edit.oldValue,
                    newValue: edit.newValue,
                    primaryKeyValues: edit.primaryKeyValues
                )
            )
        case .insert(let mutation):
            guard let next = MutationRowIndex.afterDelete(mutation.row, deleted: deletedRow) else { return nil }
            return .insert(RowMutation(table: mutation.table, row: next, values: mutation.values, primaryKeyValues: mutation.primaryKeyValues))
        case .delete(let mutation):
            guard let next = MutationRowIndex.afterDelete(mutation.row, deleted: deletedRow) else { return nil }
            return .delete(RowMutation(table: mutation.table, row: next, values: mutation.values, primaryKeyValues: mutation.primaryKeyValues))
        }
    }

    func shifting(insertedRow: Int) -> ResultMutation {
        switch self {
        case .cell(let edit):
            return .cell(
                CellEdit(
                    table: edit.table,
                    row: MutationRowIndex.afterInsert(edit.row, inserted: insertedRow),
                    column: edit.column,
                    oldValue: edit.oldValue,
                    newValue: edit.newValue,
                    primaryKeyValues: edit.primaryKeyValues
                )
            )
        case .insert(let mutation):
            return .insert(
                RowMutation(
                    table: mutation.table,
                    row: MutationRowIndex.afterInsert(mutation.row, inserted: insertedRow),
                    values: mutation.values,
                    primaryKeyValues: mutation.primaryKeyValues
                )
            )
        case .delete(let mutation):
            return .delete(
                RowMutation(
                    table: mutation.table,
                    row: MutationRowIndex.afterInsert(mutation.row, inserted: insertedRow),
                    values: mutation.values,
                    primaryKeyValues: mutation.primaryKeyValues
                )
            )
        }
    }
}
