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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SparkleUpdater.shared.checkForUpdates()
                }
            }

            CommandGroup(after: .newItem) {
                Button("New Query Tab") {
                    model.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                Button("Open…") {
                    model.openQueryFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Import CSV…") {
                    model.requestImportCSV()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.selectedConnectionID == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    model.saveActiveQueryFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.selectedTabID == nil)
                Button("Save As…") {
                    model.saveActiveQueryFileAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.selectedTabID == nil)
            }
            CommandGroup(after: .saveItem) {
                Button("Close Tab") {
                    if let tabID = model.selectedTabID {
                        model.closeTab(tabID)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(model.selectedTabID == nil)
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
                .keyboardShortcut(".", modifiers: .command)
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
                Button("Generate with AI") {
                    model.toggleEditorAIComposer()
                }
                .keyboardShortcut("k", modifiers: .command)
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
                .keyboardShortcut("k", modifiers: [.command, .shift])
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
                .disabled(!model.canCopySelectedRows)
                Button("Add Row") {
                    model.addResultRowHandler?()
                }
                .disabled(!model.canAddResultRow)
                Button("Delete Rows") {
                    model.deleteResultRowsHandler?()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canDeleteResultRows)
                Button("Undo Cell Edit") {
                    guard let tabID = model.selectedTabID else { return }
                    model.undoLastEdit(tabID: tabID, resultIndex: model.selectedResultIndex[tabID] ?? 0)
                }
                .disabled(!model.canUndoCellEdit)
                Button("Redo Cell Edit") {
                    guard let tabID = model.selectedTabID else { return }
                    model.redoLastEdit(tabID: tabID, resultIndex: model.selectedResultIndex[tabID] ?? 0)
                }
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

                Button(model.inspectorVisible ? "Hide Value Inspector" : "Show Value Inspector") {
                    model.toggleInspector()
                }

                Divider()

                Button(model.focusMode ? "Exit Focus Mode" : "Focus Mode") {
                    model.toggleFocusMode()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

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

                Button("Show Previous Tab") {
                    model.cycleSelectedTab(-1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(model.document.openTabs.count < 2)
                Button("Show Next Tab") {
                    model.cycleSelectedTab(1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(model.document.openTabs.count < 2)

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
