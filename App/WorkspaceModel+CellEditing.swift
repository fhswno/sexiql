import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Cell editing

    func resolveEditable(for result: StatementResult, profileID: UUID) async {
        guard !result.model.columns.isEmpty else { return }
        result.isResolvingEditable = true
        defer { result.isResolvingEditable = false }
        guard let connection = await connectionManager.connection(for: profileID) else { return }
        do {
            result.editableTable = try await EditableTableResolver().resolve(for: connection, columns: result.sqlColumns)
        } catch {
            result.editableTable = nil
        }
    }

    var canUndoCellEdit: Bool {
        guard let tabID = selectedTabID,
              let index = selectedResultIndex[tabID],
              let result = results[tabID]?[index] else { return false }
        return !result.undoStack.isEmpty
    }

    var canRedoCellEdit: Bool {
        guard let tabID = selectedTabID,
              let index = selectedResultIndex[tabID],
              let result = results[tabID]?[index] else { return false }
        return !result.redoStack.isEmpty
    }

    func handleCellEdit(tabID: UUID, resultIndex: Int, row: Int, column: Int, newValue: SQLValue) {
        if busyProfileID != nil {
            activeError = "A query is running. Stop it before editing cells."
            return
        }
        guard let result = results[tabID]?[resultIndex], result.status == .complete,
              let editable = result.editableTable, editable.columns.indices.contains(column) else {
            return
        }
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        let oldValue = result.model[row, column]
        let primaryKeyValues: [SQLValue] = editable.primaryKey.map { pkColumn in
            guard let index = editable.columns.firstIndex(of: pkColumn) else { return .null }
            return result.model[row, index]
        }
        guard !primaryKeyValues.contains(.null) else {
            editingMessage = "Cannot edit a row whose primary key is NULL."
            return
        }
        let edit = CellEdit(
            table: editable,
            row: row,
            column: column,
            oldValue: oldValue,
            newValue: newValue,
            primaryKeyValues: primaryKeyValues
        )
        Task { await applyEdit(edit, to: result, profileID: profileID, pushRedo: false) }
    }

    func undoLastEdit(tabID: UUID, resultIndex: Int) {
        guard let result = results[tabID]?[resultIndex], let edit = result.undoStack.popLast() else { return }
        let inverse = CellEdit(
            table: edit.table,
            row: edit.row,
            column: edit.column,
            oldValue: edit.newValue,
            newValue: edit.oldValue,
            primaryKeyValues: edit.primaryKeyValues
        )
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        Task { await applyEdit(inverse, to: result, profileID: profileID, pushRedo: true, redoOriginal: edit) }
    }

    func redoLastEdit(tabID: UUID, resultIndex: Int) {
        guard let result = results[tabID]?[resultIndex], let edit = result.redoStack.popLast() else { return }
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        Task { await applyEdit(edit, to: result, profileID: profileID, pushRedo: false) }
    }

    func applyEdit(
        _ edit: CellEdit,
        to result: StatementResult,
        profileID: UUID,
        pushRedo: Bool,
        redoOriginal: CellEdit? = nil
    ) async {
        guard let connection = await connectionManager.connection(for: profileID) else {
            editingMessage = "Not connected"
            return
        }
        let kind = document.connections.first(where: { $0.id == profileID })?.kind ?? .postgres
        let (sql, parameters) = Self.updateSQL(
            for: edit.table,
            column: edit.column,
            value: edit.newValue,
            primaryKeyValues: edit.primaryKeyValues,
            kind: kind
        )
        do {
            _ = try await connection.execute("BEGIN")
            do {
                let update = try await connection.execute(sql, parameters: parameters)
                guard update.affectedRowCount == 1 else {
                    _ = try await connection.execute("ROLLBACK")
                    editingMessage = "UPDATE affected \(update.affectedRowCount ?? 0) rows — rolled back."
                    return
                }
                _ = try await connection.execute("COMMIT")
            } catch {
                _ = try? await connection.execute("ROLLBACK")
                throw error
            }
            result.model.setValue(edit.newValue, at: edit.row, column: edit.column)
            result.model.markEdited(row: edit.row, column: edit.column)
            if pushRedo, let redoOriginal {
                result.redoStack.append(redoOriginal)
            } else if !pushRedo {
                result.undoStack.append(edit)
            }
        } catch {
            editingMessage = error.localizedDescription
        }
    }

    static func updateSQL(
        for table: EditableTable,
        column: Int,
        value: SQLValue,
        primaryKeyValues: [SQLValue],
        kind: DatabaseKind
    ) -> (sql: String, parameters: [SQLValue]) {
        let sql = CellUpdateSQL.statement(table: table, column: column, kind: kind)
        return (sql, [value] + primaryKeyValues)
    }

}
