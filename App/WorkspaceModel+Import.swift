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
        do {
            let data = try Data(contentsOf: url)
            let rows = try CSVCodec.parse(String(decoding: data, as: UTF8.self))
            guard let header = rows.first, !header.isEmpty else {
                activeError = "CSV file is empty."
                return
            }
            let session = ImportSession(csvColumns: header, csvRows: Array(rows.dropFirst()), hasHeader: true)
            session.profileID = profileID
            session.targetTable = schemaTables.first ?? ""
            importSession = session
            showingImportSheet = true
            Task { await loadImportTargetColumns() }
        } catch {
            activeError = "Could not parse CSV: \(error.localizedDescription)"
        }
    }

    func loadImportTargetColumns() async {
        guard let session = importSession, let profileID = session.profileID,
              let profile = document.connections.first(where: { $0.id == profileID }),
              let connection = await connectionManager.connection(for: profileID) else { return }
        do {
            let result: QueryResult
            if profile.kind == .sqlite {
                let escaped = session.targetTable.replacingOccurrences(of: "\"", with: "\"\"")
                result = try await connection.execute("PRAGMA table_info(\"\(escaped)\")")
                session.tableColumns = result.rows.compactMap { row in
                    if case .string(let name) = row.values[1] { name } else { nil }
                }
            } else {
                result = try await connection.execute(
                    "SELECT column_name FROM information_schema.columns WHERE table_name = $1 ORDER BY ordinal_position",
                    parameters: [.string(session.targetTable)]
                )
                session.tableColumns = result.rows.compactMap { row in
                    if case .string(let name) = row.values.first { name } else { nil }
                }
            }
            session.autoMap()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    func runImport() async {
        guard let session = importSession, let profileID = session.profileID else { return }
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
        let table = "\"" + session.targetTable.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let columns = mapped.keys
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            .joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: mapped.count).joined(separator: ", ")
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
