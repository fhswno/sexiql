import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Layout chrome

    var layout: LayoutState {
        get { document.settings.layout }
        set {
            document.settings.layout = newValue
            saveWorkspace()
        }
    }

    var sidebarVisible: Bool {
        get { layout.sidebarVisible }
        set {
            var next = layout
            next.sidebarVisible = newValue
            if newValue { next.focusMode = false }
            layout = next
        }
    }

    var resultsCollapsed: Bool {
        get { layout.resultsCollapsed }
        set {
            var next = layout
            next.resultsCollapsed = newValue
            layout = next
        }
    }

    var sidebarMode: SidebarMode {
        get { layout.sidebarMode }
        set {
            var next = layout
            next.sidebarMode = newValue
            layout = next
        }
    }

    var focusMode: Bool {
        get { layout.focusMode }
        set {
            if newValue {
                enterFocusMode()
            } else {
                exitFocusMode()
            }
        }
    }

    var appearance: AppearanceMode {
        get { document.settings.appearance }
        set {
            document.settings.appearance = newValue
            saveWorkspace()
            AppIconAppearance.apply(for: newValue)
        }
    }

    func cycleAppearance() {
        appearance = appearance.next
    }

    func openSettings(focus section: SettingsSection? = nil) {
        settingsFocusSection = section
        showingSettingsSearch = false
        let candidates = ["showSettingsWindow:", "showPreferencesWindow:"]
        for name in candidates {
            let selector = Selector(name)
            if NSApp.sendAction(selector, to: nil, from: nil) {
                return
            }
        }
    }

    func openSettingsSearch() {
        showingSettingsSearch = true
    }

    func applySettingsSearchItem(_ item: SettingsSearchItem) {
        showingSettingsSearch = false
        openSettings(focus: item.section)
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
    }

    func toggleResults() {
        resultsCollapsed.toggle()
    }

    func toggleFocusMode() {
        focusMode.toggle()
    }

    func setSidebarMode(_ mode: SidebarMode) {
        sidebarMode = mode
        if !sidebarVisible {
            sidebarVisible = true
        }
    }

    func enterFocusMode() {
        var next = layout
        next.preFocusSidebarVisible = next.sidebarVisible
        next.sidebarVisible = false
        next.inspectorVisible = false
        next.preFocusInspectorVisible = nil
        next.focusMode = true
        layout = next
        aiPanelVisible = false
    }

    func exitFocusMode() {
        var next = layout
        next.sidebarVisible = next.preFocusSidebarVisible ?? true
        next.preFocusSidebarVisible = nil
        next.inspectorVisible = false
        next.preFocusInspectorVisible = nil
        next.focusMode = false
        layout = next
    }

    func showsResultsPane(for tabID: UUID?) -> Bool {
        guard let tabID, !resultsCollapsed else { return false }
        if explainPlans[tabID] != nil || explainErrors[tabID] != nil { return true }
        if let results = results[tabID], !results.isEmpty { return true }
        return false
    }

    func exitFocusModeKeepingAI() {
        var next = layout
        next.sidebarVisible = next.preFocusSidebarVisible ?? true
        next.preFocusSidebarVisible = nil
        next.inspectorVisible = false
        next.preFocusInspectorVisible = nil
        next.focusMode = false
        layout = next
    }

}
