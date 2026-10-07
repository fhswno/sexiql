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

        if !model.isToolbarButtonHidden(.canvas) {
        ToolbarItem(placement: .primaryAction) {

            Button {
                model.newCanvasTab(profileID: model.selectedConnectionID)
            } label: {
                Label("Schema Canvas", systemImage: "flowchart")
            }
            .help("New Schema Canvas (⌘⇧C)").pointerCursor()
            .disabled(!model.canOpenCanvasTab)
        }

        }
        if !model.isToolbarButtonHidden(.run) {
        ToolbarItem(placement: .primaryAction) {

            if model.isQueryRunning(on: model.selectedTabID) {
                Button {
                    if let tabID = model.selectedTabID {
                        model.cancelRun(tabID)
                    }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop running query (⌘.)").pointerCursor()
            } else {
                Button {
                    if let tabID = model.selectedTabID {
                        model.run(tabID)
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .help("Run Query (⌘⏎)").pointerCursor()
                .disabled(model.selectedTabID == nil || model.selectedTabIsCanvas)
            }
        }

        }
        if !model.isToolbarButtonHidden(.explain) {
        ToolbarItem(placement: .primaryAction) {

            Button {
                if let tabID = model.selectedTabID {
                    model.explain(tabID)
                }
            } label: {
                Label("Explain Plan", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .help("Show engine query plan (⌘E). Uses selection when text is highlighted.").pointerCursor()
            .disabled(model.selectedTabID == nil || model.selectedTabIsCanvas || (model.selectedTabID.map { model.explainingTabs.contains($0) } ?? true))
        }

        }
        if !model.isToolbarButtonHidden(.explainAI) {
        ToolbarItem(placement: .primaryAction) {

            Button {
                if let tabID = model.selectedTabID {
                    model.explainWithAI(tabID)
                }
            } label: {
                Label("Explain with AI", systemImage: "sparkles")
            }
            .help("Explain SQL with local Ollama (⌘⇧E). Opens AI panel. Uses selection when highlighted.").pointerCursor()
            .disabled(model.selectedTabID == nil || model.selectedTabIsCanvas)
        }

        }
        if !model.isToolbarButtonHidden(.clear) {
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
            .help("Clear Results (⌘⇧K)").pointerCursor()
            .disabled(model.selectedTabID == nil)
        }

        }
        if !model.isToolbarButtonHidden(.results) {
        ToolbarItem(placement: .primaryAction) {

            Button {
                model.toggleResults()
            } label: {
                Label(
                    model.resultsCollapsed ? "Show Results" : "Hide Results",
                    systemImage: model.resultsCollapsed ? "rectangle.bottomhalf.inset.filled" : "rectangle.bottomhalf.filled"
                )
            }
            .help("Show/Hide Results Pane (⌘J)").pointerCursor()
        }

        }
        if !model.isToolbarButtonHidden(.aiPanel) {
        ToolbarItem(placement: .primaryAction) {

            Button {
                model.toggleAIPanel()
            } label: {
                Label(
                    model.aiPanelVisible ? "Hide AI Panel" : "Show AI Panel",
                    systemImage: "sidebar.right"
                )
            }
            .help(model.aiPanelVisible ? "Hide AI Panel (⇧⌘B)" : "Show AI Panel (⇧⌘B)").pointerCursor()
        }

        }
        if !model.isToolbarButtonHidden(.focus) {
        ToolbarItem(placement: .primaryAction) {

            Button {
                model.toggleFocusMode()
            } label: {
                Label(
                    model.focusMode ? "Exit Focus" : "Focus Mode",
                    systemImage: model.focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                )
            }
            .help(model.focusMode ? "Exit Focus Mode (⌘⌥F)" : "Focus Mode (⌘⌥F)").pointerCursor()
        }
    }

        ToolbarItem(placement: .primaryAction) {
            ToolbarCustomizeButton()
        }
    }

}

struct ToolbarCustomizeButton: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Label("Customize Toolbar", systemImage: "ellipsis")
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ToolbarCustomizationPopover()
        }
        .help("Customize Toolbar").pointerCursor()
    }
}

struct ToolbarCustomizationPopover: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var hoverShowAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Toolbar")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Choose which actions appear in the toolbar.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.hiddenToolbarButtons.isEmpty {
                    Button {
                        model.showAllToolbarButtons()
                    } label: {
                        Text("Show All")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.primary.opacity(hoverShowAll ? 0.14 : 0.08))
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    Color.primary.opacity(hoverShowAll ? 0.3 : 0.16),
                                    lineWidth: 1
                                )
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .onHover { hoverShowAll = $0 }
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(WorkspaceModel.ToolbarButtonID.allCases, id: \.self) { id in
                    ToolbarCustomizationTile(id: id)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ToolbarCustomizationTile: View {
    @Environment(WorkspaceModel.self) private var model
    let id: WorkspaceModel.ToolbarButtonID

    var body: some View {
        let isHidden = model.isToolbarButtonHidden(id)
        Button {
            model.setToolbarButtonHidden(id, hidden: !isHidden)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: id.systemImage)
                    .font(.system(size: 15))
                    .frame(height: 18)
                Text(id.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isHidden ? 0.04 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHidden ? 0.08 : 0.14), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if !isHidden {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 5, y: -5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(isHidden ? "Show \(id.title) button" : "Hide \(id.title) button")
    }
}
