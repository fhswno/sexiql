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
        document.selectedConnectionID = selectedConnectionID
        document.reconnectProfileIDs = connectedProfileIDs()
        try? store.save(document)
    }

    func persistSessionToDisk() {
        var snapshot = document
        snapshot.openTabs = document.openTabs.map { tab in
            var updated = tab
            updated.sql = tabTexts[tab.id] ?? tab.sql
            return updated
        }
        snapshot.selectedTabID = selectedTabID
        snapshot.selectedConnectionID = selectedConnectionID
        snapshot.reconnectProfileIDs = connectedProfileIDs()
        try? store.save(snapshot)
    }

    private func connectedProfileIDs() -> [UUID] {
        connectionStatuses.compactMap { id, status in
            if case .connected = status { return id }
            return nil
        }
    }
}
