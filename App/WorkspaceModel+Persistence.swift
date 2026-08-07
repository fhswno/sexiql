import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Persistence

    func scheduleSaveWorkspace(delay: TimeInterval = 0.35) {
        pendingWorkspaceSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveWorkspace()
        }
        pendingWorkspaceSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func saveWorkspace() {
        pendingWorkspaceSave?.cancel()
        pendingWorkspaceSave = nil
        document.openTabs = document.openTabs.map { tab in
            var updated = tab
            updated.sql = tabTexts[tab.id] ?? tab.sql
            return updated
        }
        document.selectedTabID = selectedTabID
        try? store.save(document)
    }
}
