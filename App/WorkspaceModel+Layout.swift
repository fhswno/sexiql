import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Layout Chrome

    enum ToolbarButtonID: String, CaseIterable {
        case canvas
        case run
        case explain
        case explainAI
        case clear
        case results
        case aiPanel
        case focus

        var title: String {
            switch self {
            case .canvas: "Schema Canvas"
            case .run: "Run Query"
            case .explain: "Explain Plan"
            case .explainAI: "Explain with AI"
            case .clear: "Clear Results"
            case .results: "Results Pane"
            case .aiPanel: "AI Panel"
            case .focus: "Focus Mode"
            }
        }

        var systemImage: String {
            switch self {
            case .canvas: "flowchart"
            case .run: "play.fill"
            case .explain: "point.3.connected.trianglepath.dotted"
            case .explainAI: "sparkles"
            case .clear: "trash"
            case .results: "rectangle.bottomhalf.filled"
            case .aiPanel: "sidebar.right"
            case .focus: "arrow.up.left.and.arrow.down.right"
            }
        }
    }

    var hiddenToolbarButtons: Set<ToolbarButtonID> {
        Set(document.settings.hiddenToolbarButtons.compactMap(ToolbarButtonID.init(rawValue:)))
    }

    func isToolbarButtonHidden(_ id: ToolbarButtonID) -> Bool {
        document.settings.hiddenToolbarButtons.contains(id.rawValue)
    }

    func setToolbarButtonHidden(_ id: ToolbarButtonID, hidden: Bool) {
        var hiddenIDs = Set(document.settings.hiddenToolbarButtons)
        if hidden {
            hiddenIDs.insert(id.rawValue)
        } else {
            hiddenIDs.remove(id.rawValue)
        }
        document.settings.hiddenToolbarButtons = hiddenIDs.sorted()
        scheduleSaveWorkspace()
    }

    func showAllToolbarButtons() {
        guard !document.settings.hiddenToolbarButtons.isEmpty else { return }
        document.settings.hiddenToolbarButtons = []
        scheduleSaveWorkspace()
    }

    // MARK: - Layout Chrome

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

    var inspectorVisible: Bool {
        get { layout.inspectorVisible }
        set {
            var next = layout
            next.inspectorVisible = newValue
            layout = next
        }
    }

    func toggleInspector() {
        inspectorVisible.toggle()
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

    var copySelectedRowsFormat: CopySelectedRowsFormat {
        get { document.settings.copySelectedRowsFormat }
        set {
            document.settings.copySelectedRowsFormat = newValue
            saveWorkspace()
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
