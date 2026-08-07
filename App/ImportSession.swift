import Foundation

@MainActor
@Observable
final class ImportSession: Identifiable {
    let id = UUID()
    var profileID: UUID?
    var csvColumns: [String]
    var csvRows: [[String]]
    var hasHeader = true
    var targetTable = ""
    var tableColumns: [String] = []
    var mapping: [String: String] = [:]
    var isRunning = false
    var inserted = 0
    var failed = 0
    var errorMessage: String?

    init(csvColumns: [String], csvRows: [[String]], hasHeader: Bool) {
        self.csvColumns = csvColumns
        self.csvRows = csvRows
        self.hasHeader = hasHeader
    }

    func autoMap() {
        for tableColumn in tableColumns {
            if mapping[tableColumn] == nil, csvColumns.contains(tableColumn) {
                mapping[tableColumn] = tableColumn
            }
        }
    }

    var previewRows: [[String]] {
        Array(csvRows.prefix(5))
    }
}
