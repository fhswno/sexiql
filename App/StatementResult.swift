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
    var undoStack: [CellEdit] = []
    var redoStack: [CellEdit] = []
    var filterText = ""
    var appliedLimit: Int?

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
