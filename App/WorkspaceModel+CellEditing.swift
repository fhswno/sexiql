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
            if connection.profile.kind == .redis {
                let tokens = RedisCommand.tokenize(result.label)
                result.editableTable = RedisEdit.table(forCommand: tokens, columns: result.sqlColumns)
            } else {
                result.editableTable = try await EditableTableResolver().resolve(for: connection, columns: result.sqlColumns)
            }
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
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        if isProfileBusy(profileID) {
            activeError = "A query is running. Stop it before editing cells."
            return
        }
        if document.connections.first(where: { $0.id == profileID })?.readOnly == true {
            activeError = "Connection is read-only."
            return
        }
        guard let result = results[tabID]?[resultIndex], result.status == .complete,
              let editable = result.editableTable, editable.columns.indices.contains(column) else {
            return
        }
        if result.draftRowIndex == row {
            result.model.setValue(newValue, at: row, column: column)
            Task { await commitDraftIfReady(result, profileID: profileID) }
            return
        }
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
        Task { await applyMutation(.cell(edit), to: result, profileID: profileID, pushRedo: false) }
    }

    func addResultRow(tabID: UUID, resultIndex: Int) {
        let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID
        if isProfileBusy(profileID) {
            activeError = "A query is running. Stop it before inserting a row."
            return
        }
        if profileID.map({ id in document.connections.first(where: { $0.id == id })?.readOnly == true }) == true {
            activeError = "Connection is read-only."
            return
        }
        guard let result = results[tabID]?[resultIndex], result.status == .complete,
              result.editableTable != nil else { return }
        if let existing = result.draftRowIndex, result.model.rows.indices.contains(existing) {
            result.message = "Finish the new row first."
            return
        }
        let blanks = Array(repeating: SQLValue.null, count: result.model.columns.count)
        let index = result.model.rows.count
        result.model.insertRow(SQLRow(values: blanks), at: index)
        result.draftRowIndex = index
        Task { await ensureDraftSchemaColumns(result) }
        let missing = DraftRowRequirements.missing(
            columns: draftColumns(for: result),
            values: blanks,
            primaryKey: result.editableTable?.primaryKey ?? []
        )
        if missing.isEmpty {
            result.message = "New row — edit a cell to save."
        } else {
            result.message = "Fill \(missing.joined(separator: ", ")) to save."
        }
    }

    func requestDeleteResultRows(tabID: UUID, resultIndex: Int, rows: [Int]) {
        let unique = Array(Set(rows)).sorted()
        guard !unique.isEmpty else { return }
        if unique.count > 1 {
            pendingDeleteRows = (tabID, resultIndex, unique)
            return
        }
        deleteResultRows(tabID: tabID, resultIndex: resultIndex, rows: unique)
    }

    func confirmPendingDelete() {
        guard let pending = pendingDeleteRows else { return }
        pendingDeleteRows = nil
        deleteResultRows(tabID: pending.tabID, resultIndex: pending.resultIndex, rows: pending.rows)
    }

    func cancelPendingDelete() {
        pendingDeleteRows = nil
    }

    func deleteResultRows(tabID: UUID, resultIndex: Int, rows: [Int]) {
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        if isProfileBusy(profileID) {
            activeError = "A query is running. Stop it before deleting rows."
            return
        }
        if document.connections.first(where: { $0.id == profileID })?.readOnly == true {
            activeError = "Connection is read-only."
            return
        }
        guard let result = results[tabID]?[resultIndex], result.status == .complete,
              result.editableTable != nil else { return }
        Task { await deleteRows(rows.sorted(), from: result, profileID: profileID) }
    }

    func undoLastEdit(tabID: UUID, resultIndex: Int) {
        guard let result = results[tabID]?[resultIndex], let mutation = result.undoStack.popLast() else { return }
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        Task { await applyMutation(inverse(mutation), to: result, profileID: profileID, pushRedo: true, redoOriginal: mutation) }
    }

    func redoLastEdit(tabID: UUID, resultIndex: Int) {
        guard let result = results[tabID]?[resultIndex], let mutation = result.redoStack.popLast() else { return }
        guard let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID else { return }
        Task { await applyMutation(mutation, to: result, profileID: profileID, pushRedo: false) }
    }

    func applyMutation(
        _ mutation: ResultMutation,
        to result: StatementResult,
        profileID: UUID,
        pushRedo: Bool,
        redoOriginal: ResultMutation? = nil
    ) async {
        switch mutation {
        case .cell(let edit):
            await applyCellEdit(edit, to: result, profileID: profileID, pushRedo: pushRedo, redoOriginal: redoOriginal)
        case .insert(let row):
            await applyInsert(row, to: result, profileID: profileID, pushRedo: pushRedo, redoOriginal: redoOriginal)
        case .delete(let row):
            await applyDelete(row, to: result, profileID: profileID, pushRedo: pushRedo, redoOriginal: redoOriginal)
        }
    }

    func applyEdit(
        _ edit: CellEdit,
        to result: StatementResult,
        profileID: UUID,
        pushRedo: Bool,
        redoOriginal: CellEdit? = nil
    ) async {
        let original: ResultMutation? = redoOriginal.map { .cell($0) }
        await applyCellEdit(edit, to: result, profileID: profileID, pushRedo: pushRedo, redoOriginal: original)
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

    // MARK: Internals

    private func inverse(_ mutation: ResultMutation) -> ResultMutation {
        switch mutation {
        case .cell(let edit):
            return .cell(
                CellEdit(
                    table: edit.table,
                    row: edit.row,
                    column: edit.column,
                    oldValue: edit.newValue,
                    newValue: edit.oldValue,
                    primaryKeyValues: edit.primaryKeyValues
                )
            )
        case .insert(let row):
            return .delete(row)
        case .delete(let row):
            return .insert(row)
        }
    }

    private func applyCellEdit(
        _ edit: CellEdit,
        to result: StatementResult,
        profileID: UUID,
        pushRedo: Bool,
        redoOriginal: ResultMutation?
    ) async {
        guard let connection = await connectionManager.connection(for: profileID) else {
            editingMessage = "Not connected"
            return
        }
        let kind = profileKind(profileID)
        do {
            if kind == .redis {
                guard let command = RedisEdit.updateCommand(
                    table: edit.table,
                    column: edit.column,
                    newValue: edit.newValue,
                    primaryKeyValues: edit.primaryKeyValues
                ) else {
                    editingMessage = "That Redis field is not editable."
                    return
                }
                _ = try await connection.execute(command)
            } else {
                let (sql, parameters) = Self.updateSQL(
                    for: edit.table,
                    column: edit.column,
                    value: edit.newValue,
                    primaryKeyValues: edit.primaryKeyValues,
                    kind: kind
                )
                try await withTransaction(on: connection) {
                    let update = try await connection.execute(sql, parameters: parameters)
                    guard update.affectedRowCount == 1 else {
                        throw RowWriteError.unexpectedCount(update.affectedRowCount ?? 0, verb: "UPDATE")
                    }
                }
            }
            let row = rowIndex(matching: edit.primaryKeyValues, table: edit.table, in: result.model) ?? edit.row
            result.model.setValue(edit.newValue, at: row, column: edit.column)
            result.model.markEdited(row: row, column: edit.column)
            recordMutation(.cell(edit), on: result, pushRedo: pushRedo, redoOriginal: redoOriginal)
        } catch {
            editingMessage = error.localizedDescription
        }
    }

    private func commitDraftIfReady(_ result: StatementResult, profileID: UUID) async {
        guard let table = result.editableTable, let draft = result.draftRowIndex,
              result.model.rows.indices.contains(draft) else { return }
        await ensureDraftSchemaColumns(result)
        let values = result.model.rows[draft].values
        let missing = DraftRowRequirements.missing(
            columns: draftColumns(for: result),
            values: values,
            primaryKey: table.primaryKey
        )
        if !missing.isEmpty {
            result.message = "Fill \(missing.joined(separator: ", ")) to save."
            return
        }
        guard let connection = await connectionManager.connection(for: profileID) else {
            result.message = "Not connected"
            return
        }
        let kind = profileKind(profileID)
        var names: [String] = []
        var params: [SQLValue] = []
        let pk = Set(table.primaryKey.map { $0.lowercased() })
        for (index, name) in table.columns.enumerated() {
            let value = values.indices.contains(index) ? values[index] : .null
            if pk.contains(name.lowercased()), value == .null { continue }
            names.append(name)
            params.append(value)
        }
        guard !names.isEmpty else {
            result.message = "Fill required columns to save."
            return
        }
        do {
            if kind == .redis {
                guard let command = RedisEdit.insertCommand(table: table, columns: names, values: params) else {
                    result.message = "Cannot insert that Redis value."
                    return
                }
                _ = try await connection.execute(command)
                let saved = (row: SQLRow(values: values), pk: primaryKeyValues(table: table, values: values, columns: table.columns))
                result.model.removeRow(at: draft)
                result.model.insertRow(saved.row, at: draft)
                result.draftRowIndex = nil
                result.message = nil
                result.undoStack = result.undoStack.map { $0.shifting(insertedRow: draft) }
                result.redoStack = []
                result.undoStack.append(
                    .insert(
                        RowMutation(table: table, row: draft, values: saved.row.values, primaryKeyValues: saved.pk)
                    )
                )
                return
            }
            let sql = CellInsertSQL.explicit(table: table, columnNames: names, kind: kind)
            let saved = try await withTransaction(on: connection) {
                let inserted = try await connection.execute(sql, parameters: params)
                if let mapped = mapReturnedRow(inserted, to: result.sqlColumns) {
                    let pk = primaryKeyValues(table: table, values: mapped.values, columns: table.columns)
                    return (row: mapped, pk: pk)
                }
                if let returned = try await fetchInsertedRow(
                    table: table,
                    result: result,
                    connection: connection,
                    kind: kind,
                    fallbackValues: values
                ) {
                    return returned
                }
                return (row: SQLRow(values: values), pk: primaryKeyValues(table: table, values: values, columns: table.columns))
            }
            result.model.removeRow(at: draft)
            result.model.insertRow(saved.row, at: draft)
            result.draftRowIndex = nil
            result.message = nil
            result.undoStack = result.undoStack.map { $0.shifting(insertedRow: draft) }
            result.redoStack = []
            result.undoStack.append(
                .insert(
                    RowMutation(table: table, row: draft, values: saved.row.values, primaryKeyValues: saved.pk)
                )
            )
        } catch {
            result.message = error.localizedDescription
        }
    }

    private func draftColumns(for result: StatementResult) -> [SQLColumn] {
        let table = result.editableTable
        let object = schemaObjects.first {
            $0.name.caseInsensitiveCompare(table?.name ?? "") == .orderedSame
                || $0.displayName.caseInsensitiveCompare(table?.name ?? "") == .orderedSame
        }
        let schemaCols = object.flatMap { schemaColumnsByID[$0.id] } ?? []
        return result.sqlColumns.map { column in
            var next = column
            if let schema = schemaCols.first(where: { $0.name.caseInsensitiveCompare(column.name) == .orderedSame }) {
                next.isNullable = schema.isNullable
            }
            return next
        }
    }

    private func ensureDraftSchemaColumns(_ result: StatementResult) async {
        guard let table = result.editableTable else { return }
        let object = schemaObjects.first {
            $0.name.caseInsensitiveCompare(table.name) == .orderedSame
                || $0.displayName.caseInsensitiveCompare(table.name) == .orderedSame
        }
        guard let object, schemaColumnsByID[object.id] == nil else { return }
        await loadSchemaColumns(object, reportError: false)
    }

    private func fetchInsertedRow(
        table: EditableTable,
        result: StatementResult,
        connection: any DatabaseConnection,
        kind: DatabaseKind,
        fallbackValues: [SQLValue]
    ) async throws -> (row: SQLRow, pk: [SQLValue])? {
        if kind == .postgres || kind == .sqlite {
            if let idSQL = CellInsertSQL.lastInsertID(kind: kind) {
                let idResult = try await connection.execute(idSQL)
                if let idValue = idResult.rows.first?.values.first, idValue != .null, idValue != .int(0),
                   table.primaryKey.count == 1 {
                    let select = CellInsertSQL.selectByPrimaryKey(
                        table: table,
                        selectColumns: result.sqlColumns.map(\.name),
                        kind: kind
                    )
                    let fetched = try await connection.execute(select, parameters: [idValue])
                    if let mapped = mapReturnedRow(fetched, to: result.sqlColumns) {
                        return (mapped, [idValue])
                    }
                }
            }
        }
        if kind == .mysql, let idSQL = CellInsertSQL.lastInsertID(kind: kind) {
            let idResult = try await connection.execute(idSQL)
            if let idValue = idResult.rows.first?.values.first, idValue != .null, idValue != .int(0),
               table.primaryKey.count == 1 {
                let select = CellInsertSQL.selectByPrimaryKey(
                    table: table,
                    selectColumns: result.sqlColumns.map(\.name),
                    kind: kind
                )
                let fetched = try await connection.execute(select, parameters: [idValue])
                if let mapped = mapReturnedRow(fetched, to: result.sqlColumns) {
                    return (mapped, [idValue])
                }
            }
        }
        let pk = primaryKeyValues(table: table, values: fallbackValues, columns: table.columns)
        if !pk.contains(.null) {
            return (SQLRow(values: fallbackValues), pk)
        }
        return nil
    }

    private func insertDefaultRow(into result: StatementResult, profileID: UUID) async {
        guard let table = result.editableTable else { return }
        guard let connection = await connectionManager.connection(for: profileID) else {
            editingMessage = "Not connected"
            return
        }
        let kind = profileKind(profileID)
        do {
            let inserted = try await withTransaction(on: connection) {
                try await performInsert(table: table, result: result, connection: connection, kind: kind)
            }
            let index = result.model.rows.count
            result.model.insertRow(inserted.row, at: index)
            result.undoStack = result.undoStack.map { $0.shifting(insertedRow: index) }
            result.redoStack = []
            result.undoStack.append(
                .insert(
                    RowMutation(
                        table: table,
                        row: index,
                        values: inserted.row.values,
                        primaryKeyValues: inserted.pk
                    )
                )
            )
        } catch {
            editingMessage = error.localizedDescription
            activeError = error.localizedDescription
        }
    }

    private func deleteRows(_ rows: [Int], from result: StatementResult, profileID: UUID) async {
        guard let table = result.editableTable else { return }
        guard let connection = await connectionManager.connection(for: profileID) else {
            editingMessage = "Not connected"
            return
        }
        let kind = profileKind(profileID)
        let sql = CellDeleteSQL.statement(table: table, kind: kind)
        let descending = rows.sorted(by: >)
        var planned: [(index: Int, values: [SQLValue], pk: [SQLValue])] = []
        for index in descending {
            guard result.model.rows.indices.contains(index) else { continue }
            if result.draftRowIndex == index {
                result.model.removeRow(at: index)
                result.draftRowIndex = nil
                result.message = nil
                result.undoStack = result.undoStack.compactMap { $0.shifting(deletedRow: index) }
                continue
            }
            let pk = primaryKeyValues(table: table, row: index, in: result.model)
            guard !pk.contains(.null) else {
                editingMessage = "Cannot delete a row whose primary key is NULL."
                return
            }
            planned.append((index, result.model.rows[index].values, pk))
        }
        guard !planned.isEmpty else { return }
        do {
            if kind == .redis {
                for item in planned {
                    guard let command = RedisEdit.deleteCommand(table: table, primaryKeyValues: item.pk) else {
                        throw RowWriteError.missingPrimaryKey
                    }
                    _ = try await connection.execute(command)
                }
            } else {
                try await withTransaction(on: connection) {
                    for item in planned {
                        let deleted = try await connection.execute(sql, parameters: item.pk)
                        guard deleted.affectedRowCount == 1 else {
                            throw RowWriteError.unexpectedCount(deleted.affectedRowCount ?? 0, verb: "DELETE")
                        }
                    }
                }
            }
            for item in planned {
                result.model.removeRow(at: item.index)
                result.undoStack = result.undoStack.compactMap { $0.shifting(deletedRow: item.index) }
                result.undoStack.append(
                    .delete(
                        RowMutation(table: table, row: item.index, values: item.values, primaryKeyValues: item.pk)
                    )
                )
            }
            result.redoStack = []
        } catch {
            editingMessage = error.localizedDescription
            activeError = error.localizedDescription
        }
    }

    private func applyInsert(
        _ mutation: RowMutation,
        to result: StatementResult,
        profileID: UUID,
        pushRedo: Bool,
        redoOriginal: ResultMutation?
    ) async {
        guard let connection = await connectionManager.connection(for: profileID) else {
            editingMessage = "Not connected"
            return
        }
        let kind = profileKind(profileID)
        do {
            if kind == .redis {
                guard let command = RedisEdit.insertCommand(
                    table: mutation.table,
                    columns: mutation.table.columns,
                    values: mutation.values
                ) else {
                    editingMessage = "Cannot insert that Redis value."
                    return
                }
                _ = try await connection.execute(command)
            } else {
                let sql = CellInsertSQL.explicit(table: mutation.table, columnNames: mutation.table.columns, kind: kind)
                try await withTransaction(on: connection) {
                    let inserted = try await connection.execute(sql, parameters: mutation.values)
                    let count = inserted.affectedRowCount ?? inserted.rows.count
                    guard count == 1 || !inserted.rows.isEmpty else {
                        throw RowWriteError.unexpectedCount(count, verb: "INSERT")
                    }
                }
            }
            let index = min(max(mutation.row, 0), result.model.rows.count)
            result.model.insertRow(SQLRow(values: mutation.values), at: index)
            result.undoStack = result.undoStack.map { $0.shifting(insertedRow: index) }
            recordMutation(.insert(mutation), on: result, pushRedo: pushRedo, redoOriginal: redoOriginal)
        } catch {
            editingMessage = error.localizedDescription
        }
    }

    private func applyDelete(
        _ mutation: RowMutation,
        to result: StatementResult,
        profileID: UUID,
        pushRedo: Bool,
        redoOriginal: ResultMutation?
    ) async {
        guard let connection = await connectionManager.connection(for: profileID) else {
            editingMessage = "Not connected"
            return
        }
        let kind = profileKind(profileID)
        do {
            if kind == .redis {
                guard let command = RedisEdit.deleteCommand(
                    table: mutation.table,
                    primaryKeyValues: mutation.primaryKeyValues
                ) else {
                    editingMessage = "Cannot delete that Redis value."
                    return
                }
                _ = try await connection.execute(command)
            } else {
                let sql = CellDeleteSQL.statement(table: mutation.table, kind: kind)
                try await withTransaction(on: connection) {
                    let deleted = try await connection.execute(sql, parameters: mutation.primaryKeyValues)
                    guard deleted.affectedRowCount == 1 else {
                        throw RowWriteError.unexpectedCount(deleted.affectedRowCount ?? 0, verb: "DELETE")
                    }
                }
            }
            let row = rowIndex(matching: mutation.primaryKeyValues, table: mutation.table, in: result.model)
                ?? mutation.row
            if result.model.rows.indices.contains(row) {
                result.model.removeRow(at: row)
                result.undoStack = result.undoStack.compactMap { $0.shifting(deletedRow: row) }
            }
            recordMutation(.delete(mutation), on: result, pushRedo: pushRedo, redoOriginal: redoOriginal)
        } catch {
            editingMessage = error.localizedDescription
        }
    }

    private func performInsert(
        table: EditableTable,
        result: StatementResult,
        connection: any DatabaseConnection,
        kind: DatabaseKind
    ) async throws -> (row: SQLRow, pk: [SQLValue]) {
        let insertSQL = CellInsertSQL.defaultValues(table: table, kind: kind)
        let inserted = try await connection.execute(insertSQL)
        if let mapped = mapReturnedRow(inserted, to: result.sqlColumns) {
            let pk = primaryKeyValues(table: table, values: mapped.values, columns: table.columns)
            guard !pk.contains(.null) else {
                throw RowWriteError.missingPrimaryKey
            }
            return (mapped, pk)
        }
        guard let idSQL = CellInsertSQL.lastInsertID(kind: kind) else {
            throw RowWriteError.missingPrimaryKey
        }
        let idResult = try await connection.execute(idSQL)
        guard let idValue = idResult.rows.first?.values.first, idValue != .null, idValue != .int(0) else {
            throw RowWriteError.missingPrimaryKey
        }
        guard table.primaryKey.count == 1 else {
            throw RowWriteError.missingPrimaryKey
        }
        let select = CellInsertSQL.selectByPrimaryKey(
            table: table,
            selectColumns: result.sqlColumns.map(\.name),
            kind: kind
        )
        let fetched = try await connection.execute(select, parameters: [idValue])
        guard let mapped = mapReturnedRow(fetched, to: result.sqlColumns) else {
            throw RowWriteError.missingPrimaryKey
        }
        return (mapped, [idValue])
    }

    private func mapReturnedRow(_ result: QueryResult, to columns: [SQLColumn]) -> SQLRow? {
        guard let returned = result.rows.first else { return nil }
        guard let returnedColumns = result.columns, !returnedColumns.isEmpty else {
            if returned.values.count == columns.count {
                return returned
            }
            return nil
        }
        var values: [SQLValue] = []
        values.reserveCapacity(columns.count)
        for column in columns {
            if let index = returnedColumns.firstIndex(where: { $0.name.caseInsensitiveCompare(column.name) == .orderedSame }),
               returned.values.indices.contains(index) {
                values.append(returned.values[index])
            } else {
                values.append(.null)
            }
        }
        return SQLRow(values: values)
    }

    private func primaryKeyValues(table: EditableTable, row: Int, in model: ResultSetModel) -> [SQLValue] {
        table.primaryKey.map { pkColumn in
            guard let index = table.columns.firstIndex(of: pkColumn) else { return .null }
            return model[row, index]
        }
    }

    private func primaryKeyValues(table: EditableTable, values: [SQLValue], columns: [String]) -> [SQLValue] {
        table.primaryKey.map { pkColumn in
            guard let index = columns.firstIndex(of: pkColumn), values.indices.contains(index) else { return .null }
            return values[index]
        }
    }

    private func rowIndex(matching pk: [SQLValue], table: EditableTable, in model: ResultSetModel) -> Int? {
        for index in model.rows.indices {
            if primaryKeyValues(table: table, row: index, in: model) == pk {
                return index
            }
        }
        return nil
    }

    private func recordMutation(
        _ mutation: ResultMutation,
        on result: StatementResult,
        pushRedo: Bool,
        redoOriginal: ResultMutation?
    ) {
        if pushRedo, let redoOriginal {
            result.redoStack.append(redoOriginal)
        } else if !pushRedo {
            result.undoStack.append(mutation)
            result.redoStack = []
        }
    }

    private func profileKind(_ profileID: UUID) -> DatabaseKind {
        document.connections.first(where: { $0.id == profileID })?.kind ?? .postgres
    }

    private func withTransaction<T>(
        on connection: any DatabaseConnection,
        _ body: () async throws -> T
    ) async throws -> T {
        if connection.profile.kind == .redis {
            return try await body()
        }
        _ = try await connection.execute("BEGIN")
        do {
            let value = try await body()
            _ = try await connection.execute("COMMIT")
            return value
        } catch {
            _ = try? await connection.execute("ROLLBACK")
            throw error
        }
    }
}

private enum RowWriteError: Error, LocalizedError {
    case unexpectedCount(Int, verb: String)
    case missingPrimaryKey

    var errorDescription: String? {
        switch self {
        case .unexpectedCount(let count, let verb):
            "\(verb) affected \(count) rows — rolled back."
        case .missingPrimaryKey:
            "Could not read the inserted primary key."
        }
    }
}
