import SwiftUI
import SQLUI

struct SexiQLToolbar: ToolbarContent {
    @Environment(WorkspaceModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            TitlebarNavigationControls()
                .frame(minHeight: 30)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .primaryAction) {
            if model.isQueryRunning(on: model.selectedTabID) {
                Button {
                    if let tabID = model.selectedTabID {
                        model.cancelRun(tabID)
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop running query (⌘⌥.)")
            } else {
                Button {
                    if let tabID = model.selectedTabID {
                        model.run(tabID)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .help("Run Query (⌘⏎)")
                .disabled(model.selectedTabID == nil)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let tabID = model.selectedTabID {
                    model.explain(tabID)
                }
            } label: {
                Label("Explain Plan", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .help("Show engine query plan (⌘E). Uses selection when text is highlighted.")
            .disabled(model.selectedTabID == nil || (model.selectedTabID.map { model.explainingTabs.contains($0) } ?? true))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let tabID = model.selectedTabID {
                    model.explainWithAI(tabID)
                }
            } label: {
                Label("Explain with AI", systemImage: "sparkles")
            }
            .help("Explain SQL with local Ollama (⌘⇧E). Opens AI panel. Uses selection when highlighted.")
            .disabled(model.selectedTabID == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                if let tabID = model.selectedTabID {
                    model.cancelRun(tabID)
                    model.results[tabID] = nil
                    model.selectedResultIndex[tabID] = nil
                    model.clearExplain(tabID)
                    model.clearAIExplain(tabID)
                }
            } label: {
                Label("Clear Results", systemImage: "trash")
            }
            .help("Clear Results (⌘⇧K)")
            .disabled(model.selectedTabID == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.toggleResults()
            } label: {
                Label(
                    model.resultsCollapsed ? "Show Results" : "Hide Results",
                    systemImage: model.resultsCollapsed ? "rectangle.bottomhalf.inset.filled" : "rectangle.bottomhalf.filled"
                )
            }
            .help("Show/Hide Results Pane (⌘⇧Y)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.toggleAIPanel()
            } label: {
                Label(
                    model.aiPanelVisible ? "Hide AI Panel" : "Show AI Panel",
                    systemImage: "sidebar.right"
                )
            }
            .help(model.aiPanelVisible ? "Hide AI Panel (⌘⌥0)" : "Show AI Panel (⌘⌥0)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.toggleFocusMode()
            } label: {
                Label(
                    model.focusMode ? "Exit Focus" : "Focus Mode",
                    systemImage: model.focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                )
            }
            .help(model.focusMode ? "Exit Focus Mode (⌘.)" : "Focus Mode (⌘.)")
        }
    }

}

