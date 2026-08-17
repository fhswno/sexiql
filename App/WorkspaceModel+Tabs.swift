import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Tabs

    @discardableResult
    func newTab(title: String = "Untitled Query", sql: String = "", titleIsCustom: Bool? = nil) -> EditorTabState {
        let resolvedTitle = uniqueTabTitle(title)
        let custom = titleIsCustom ?? !EditorTabState(title: title).isDefaultUntitledTitle
        let tab = EditorTabState(
            title: resolvedTitle,
            connectionProfileID: selectedConnectionID,
            sql: sql,
            titleIsCustom: custom
        )
        document.openTabs.append(tab)
        setTabTextExternal(tab.id, sql: sql)
        selectedTabID = tab.id
        saveWorkspace()
        return tab
    }

    func closeTab(_ tabID: UUID) {
        cancelRun(tabID)
        cancelEditorAI()
        clearAIChat(tabID)
        document.openTabs.removeAll { $0.id == tabID }
        tabTexts[tabID] = nil
        results[tabID] = nil
        selectedResultIndex[tabID] = nil
        explainPlans[tabID] = nil
        explainErrors[tabID] = nil
        if selectedTabID == tabID, let next = document.openTabs.last?.id {
            selectEditorTab(next)
        } else if selectedTabID == tabID {
            selectedTabID = nil
        }
        saveWorkspace()
    }

    func closeOtherTabs(keeping tabID: UUID) {
        let victims = document.openTabs.map(\.id).filter { $0 != tabID }
        for id in victims {
            closeTab(id)
        }
        selectedTabID = tabID
    }

    @discardableResult
    func renameTab(_ tabID: UUID, to rawTitle: String) -> Bool {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        guard let index = document.openTabs.firstIndex(where: { $0.id == tabID }) else { return false }
        document.openTabs[index].title = title
        document.openTabs[index].titleIsCustom = true
        saveWorkspace()
        return true
    }

    func requestTabRename(_ tabID: UUID? = nil) {
        pendingTabRenameID = tabID ?? selectedTabID
    }

    var selectedTabConnectionID: UUID? {
        document.openTabs.first(where: { $0.id == selectedTabID })?.connectionProfileID
    }

    func setSelectedTabConnection(_ profileID: UUID?) {
        bindActiveTab(to: profileID)
        if let profileID {
            selectedConnectionID = profileID
            if let profile = document.connections.first(where: { $0.id == profileID }),
               status(for: profileID) == .connected {
                Task { await loadSchema(for: profile) }
            }
        }
    }

    func uniqueTabTitle(_ base: String) -> String {
        let existing = Set(document.openTabs.map(\.title))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func maybeAutoTitleTab(_ tabID: UUID, fromSQL sql: String) {
        guard let index = document.openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = document.openTabs[index]
        guard !tab.titleIsCustom else { return }
        guard tab.isDefaultUntitledTitle || tab.title == "history" else { return }
        guard let derived = TabTitleDeriver.derive(from: sql) else { return }
        document.openTabs[index].title = uniqueTabTitle(derived)
        saveWorkspace()
    }

    func reorderTabs(from source: IndexSet, to destination: Int) {
        var tabs = document.openTabs
        tabs.move(fromOffsets: source, toOffset: destination)
        document.openTabs = tabs
        scheduleSaveWorkspace()
    }

    func moveTab(id: UUID, before targetID: UUID?) {
        guard id != targetID else { return }
        guard let from = document.openTabs.firstIndex(where: { $0.id == id }) else { return }
        var tabs = document.openTabs
        let item = tabs.remove(at: from)
        if let targetID, let to = tabs.firstIndex(where: { $0.id == targetID }) {
            tabs.insert(item, at: to)
        } else {
            tabs.append(item)
        }
        if tabs.map(\.id) == document.openTabs.map(\.id) { return }
        document.openTabs = tabs
        scheduleSaveWorkspace()
    }

}
