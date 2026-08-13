import AppKit
import SwiftUI
import SQLCore

@main
struct SexiQLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = WorkspaceModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 640)
                .preferredColorScheme(preferredScheme)
                .onAppear {
                    AppDelegate.shared?.workspace = model
                }
                .onDisappear {
                    model.saveWorkspace()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Query Tab") {
                    model.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Query") {
                Button("Run") {
                    if let tabID = model.selectedTabID {
                        model.run(tabID)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedTabID == nil || model.isQueryRunning(on: model.selectedTabID))
                Button("Stop") {
                    if let tabID = model.selectedTabID {
                        model.cancelRun(tabID)
                    }
                }
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(!model.isQueryRunning(on: model.selectedTabID))
                Button("Explain Plan") {
                    if let tabID = model.selectedTabID {
                        model.explain(tabID)
                    }
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.selectedTabID == nil)
                Button("Find…") {
                    model.showFindInEditor?()
                }
                .disabled(model.selectedTabID == nil)
                Button("Format") {
                    model.formatActiveEditor?()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model.selectedTabID == nil)
                Button("Explain with AI") {
                    if let tabID = model.selectedTabID {
                        model.explainWithAI(tabID)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.selectedTabID == nil)
                Button("Clear Results") {
                    if let tabID = model.selectedTabID {
                        model.cancelRun(tabID)
                        model.results[tabID] = nil
                        model.selectedResultIndex[tabID] = nil
                        model.clearExplain(tabID)
                        model.clearAIExplain(tabID)
                    }
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model.selectedTabID == nil)
                Divider()
                Button("Save Query…") {
                    model.beginSaveQuery()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.selectedTabID == nil)
                Button("Rename Tab…") {
                    model.requestTabRename()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedTabID == nil)
                Divider()
                Button("Copy Selected Rows") {
                    model.copySelectedRowsHandler?()
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!model.canCopySelectedRows)
                Button("Undo Cell Edit") {
                    guard let tabID = model.selectedTabID else { return }
                    model.undoLastEdit(tabID: tabID, resultIndex: model.selectedResultIndex[tabID] ?? 0)
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndoCellEdit)
                Button("Redo Cell Edit") {
                    guard let tabID = model.selectedTabID else { return }
                    model.redoLastEdit(tabID: tabID, resultIndex: model.selectedResultIndex[tabID] ?? 0)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedoCellEdit)
            }

            CommandMenu("View") {
                Button(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    model.toggleSidebar()
                }
                .keyboardShortcut("0", modifiers: .command)

                Button(model.aiPanelVisible ? "Hide AI Panel" : "Show AI Panel") {
                    model.toggleAIPanel()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Button(model.resultsCollapsed ? "Show Results" : "Hide Results") {
                    model.toggleResults()
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])

                Divider()

                Button(model.focusMode ? "Exit Focus Mode" : "Focus Mode") {
                    model.toggleFocusMode()
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Connections") { model.setSidebarMode(.connections) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Schema") { model.setSidebarMode(.schema) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Saved Queries") { model.setSidebarMode(.saved) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("History") { model.setSidebarMode(.history) }
                    .keyboardShortcut("4", modifiers: .command)

                Divider()

                Menu("Appearance") {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button {
                            model.appearance = mode
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                if model.appearance == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Button("Cycle Appearance") {
                    model.cycleAppearance()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Theme…") {
                    model.openSettings(focus: .appearance)
                }
            }

            CommandGroup(replacing: .help) {
                Button("Search Settings…") {
                    model.openSettingsSearch()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
                Divider()
                Button("Theme & Appearance…") {
                    model.openSettings(focus: .appearance)
                }
                Button("Workspace Settings…") {
                    model.openSettings(focus: .workspace)
                }
                Button("Layout Settings…") {
                    model.openSettings(focus: .layout)
                }
            }
        }
        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(preferredScheme)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch model.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
