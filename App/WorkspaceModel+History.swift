import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - History & saved queries

    func recordHistory(_ sql: String, profileID: UUID?) {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let connectionName = document.connections.first(where: { $0.id == profileID })?.name
        document.history.insert(
            QueryHistoryEntry(sql: trimmed, connectionProfileID: profileID, connectionName: connectionName),
            at: 0
        )
        if document.history.count > WorkspaceDocument.historyLimit {
            document.history.removeLast(document.history.count - WorkspaceDocument.historyLimit)
        }
        saveWorkspace()
    }

    var filteredHistory: [QueryHistoryEntry] {
        let query = historySearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return document.history }
        return document.history.filter { $0.sql.localizedCaseInsensitiveContains(query) }
    }

    func loadHistoryIntoEditor(_ entry: QueryHistoryEntry) {
        guard let tabID = selectedTabID else { return }
        setTabTextExternal(tabID, sql: entry.sql)
        saveWorkspace()
    }

    func rerunHistory(_ entry: QueryHistoryEntry) {
        let tab = newTab(title: "history", sql: entry.sql, titleIsCustom: false)
        if let profileID = entry.connectionProfileID {
            setTabConnection(tab.id, to: profileID)
        }
        run(tab.id)
    }

    func beginSaveQuery(sql: String? = nil, suggestedName: String? = nil) {
        let resolvedSQL: String
        if let sql, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedSQL = sql
        } else if let tabID = selectedTabID {
            resolvedSQL = tabTexts[tabID] ?? ""
        } else {
            resolvedSQL = ""
        }
        guard !resolvedSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            activeError = "Nothing to save. Select SQL in the editor or open a query tab."
            return
        }
        pendingSaveSQL = resolvedSQL
        if let suggestedName, !suggestedName.trimmingCharacters(in: .whitespaces).isEmpty {
            pendingSaveSuggestedName = suggestedName
        } else if let tabTitle = document.openTabs.first(where: { $0.id == selectedTabID })?.title,
                  !tabTitle.isEmpty {
            pendingSaveSuggestedName = tabTitle
        } else if let derived = TabTitleDeriver.derive(from: resolvedSQL) {
            pendingSaveSuggestedName = derived
        } else {
            pendingSaveSuggestedName = "Saved Query"
        }
        showingSaveQuerySheet = true
    }

    func saveQuery(name: String, sql: String? = nil) {
        let resolvedSQL = (sql ?? pendingSaveSQL)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !resolvedSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        document.savedQueries.insert(SavedQuery(name: trimmedName, sql: resolvedSQL), at: 0)
        pendingSaveSQL = ""
        pendingSaveSuggestedName = ""
        showingSaveQuerySheet = false
        if sidebarMode != .saved {
            setSidebarMode(.saved)
        }
        saveWorkspace()
    }

    func saveCurrentQuery(name: String) {
        saveQuery(name: name, sql: nil)
    }

    func openSavedQuery(_ savedQuery: SavedQuery) {
        let tab = newTab(title: savedQuery.name, sql: savedQuery.sql, titleIsCustom: true)
        if let sidebar = selectedConnectionID {
            setTabConnection(tab.id, to: sidebar)
        } else if let connected = document.connections.first(where: { status(for: $0.id) == .connected }) {
            selectedConnectionID = connected.id
            setTabConnection(tab.id, to: connected.id)
        }
    }

    func renameSavedQuery(_ savedQuery: SavedQuery, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard let index = document.savedQueries.firstIndex(where: { $0.id == savedQuery.id }) else { return }
        document.savedQueries[index].name = name
        saveWorkspace()
    }

    func deleteSavedQuery(_ savedQuery: SavedQuery) {
        document.savedQueries.removeAll { $0.id == savedQuery.id }
        saveWorkspace()
    }

    func setTabConnection(_ tabID: UUID, to profileID: UUID) {
        if let index = document.openTabs.firstIndex(where: { $0.id == tabID }) {
            document.openTabs[index].connectionProfileID = profileID
            saveWorkspace()
        }
    }

}
