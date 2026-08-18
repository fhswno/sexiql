import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Import

    func prepareImport(from url: URL, profileID: UUID) {
        if document.connections.first(where: { $0.id == profileID })?.readOnly == true {
            activeError = "Connection is read-only."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let dialect = CSVCodec.sniff(data)
            let session = try ImportSession(rawData: data, dialect: dialect, hasHeader: true)
            session.profileID = profileID
            session.targetTable = schemaTables.first ?? ""
            importSession = session
            showingImportSheet = true
            Task { await loadImportTargetColumns() }
        } catch {
            activeError = "Could not parse CSV: \(error.localizedDescription)"
        }
    }

    func reloadImportSession() {
        do {
            try importSession?.applyParse()
            importSession?.errorMessage = nil
        } catch {
            importSession?.errorMessage = error.localizedDescription
        }
    }

    func loadImportTargetColumns() async {
        guard let session = importSession, let profileID = session.profileID,
              let profile = document.connections.first(where: { $0.id == profileID }),
              let connection = await connectionManager.connection(for: profileID) else { return }
        do {
            let result: QueryResult
            switch profile.kind {
            case .sqlite:
                let quoted = SchemaBrowser.quoteIdentifier(session.targetTable, kind: .sqlite)
                result = try await connection.execute("PRAGMA table_info(\(quoted))")
                session.tableColumns = result.rows.compactMap { row in
                    if case .string(let name) = row.values[1] { name } else { nil }
                }
            case .postgres:
                result = try await connection.execute(
                    "SELECT column_name FROM information_schema.columns WHERE table_name = $1 ORDER BY ordinal_position",
                    parameters: [.string(session.targetTable)]
                )
                session.tableColumns = result.rows.compactMap { row in
                    if case .string(let name) = row.values.first { name } else { nil }
                }
            case .mysql:
                result = try await connection.execute(
                    "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION",
                    parameters: [.string(session.targetTable)]
                )
                session.tableColumns = result.rows.compactMap { row in
                    if case .string(let name) = row.values.first { name } else { nil }
                }
            case .redis:
                session.errorMessage = "CSV import is not available for Redis."
                return
            }
            session.autoMap()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    func runImport() async {
        guard let session = importSession, let profileID = session.profileID else { return }
        if document.connections.first(where: { $0.id == profileID })?.readOnly == true {
            session.errorMessage = "Connection is read-only."
            return
        }
        guard let connection = await connectionManager.connection(for: profileID) else {
            session.errorMessage = "Not connected"
            return
        }
        let mapped = session.mapping.filter { !$0.value.isEmpty }
        guard !mapped.isEmpty else {
            session.errorMessage = "Map at least one column."
            return
        }
        session.isRunning = true
        defer { session.isRunning = false }
        let kind = document.connections.first(where: { $0.id == profileID })?.kind ?? .sqlite
        let table = SchemaBrowser.quoteIdentifier(session.targetTable, kind: kind)
        let columns = mapped.keys
            .map { SchemaBrowser.quoteIdentifier($0, kind: kind) }
            .joined(separator: ", ")
        let placeholders: String
        if kind == .postgres {
            placeholders = (1...mapped.count).map { "$\($0)" }.joined(separator: ", ")
        } else {
            placeholders = Array(repeating: "?", count: mapped.count).joined(separator: ", ")
        }
        let sql = "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders))"
        let csvColumnOrder = session.csvColumns

        do {
            _ = try await connection.execute("BEGIN")
            do {
                for row in session.csvRows {
                    var parameters: [SQLValue] = []
                    parameters.reserveCapacity(mapped.count)
                    for tableColumn in mapped.keys {
                        guard let csvColumn = mapped[tableColumn],
                              let csvIndex = csvColumnOrder.firstIndex(of: csvColumn),
                              row.indices.contains(csvIndex) else {
                            parameters.append(.null)
                            continue
                        }
                        parameters.append(JSONCodec.inferredValue(row[csvIndex]))
                    }
                    do {
                        _ = try await connection.execute(sql, parameters: parameters)
                        session.inserted += 1
                    } catch {
                        session.failed += 1
                    }
                }
                _ = try await connection.execute("COMMIT")
            } catch {
                _ = try? await connection.execute("ROLLBACK")
                throw error
            }
        } catch {
            session.errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
