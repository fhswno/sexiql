import SwiftUI
import SQLCore
import SQLUI

struct EditorAreaView: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var renamingTabID: UUID?
    @State private var renameDraft = ""
    @State private var draggingTabID: UUID?
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .onChange(of: model.pendingTabRenameID) { _, newValue in
            guard let newValue else { return }
            beginRename(newValue)
            model.pendingTabRenameID = nil
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if model.document.openTabs.isEmpty {
            EmptyStateView(
                title: "No query tab open",
                subtitle: "Press ⌘T or open a table to start querying.",
                systemImage: "doc.text.magnifyingglass",
                actionTitle: "New Query"
            ) {
                model.newTab()
            }
            .background(.windowBackground)
        } else {
            let openIDs = model.document.openTabs.map(\.id)
            let selected = model.selectedTabID
            let showResults = selected.map { model.showsResultsPane(for: $0) } ?? false

            VSplitView {
                TabEditorHostRepresentable(
                    openTabIDs: openIDs,
                    selectedTabID: selected,
                    texts: model.tabTexts,
                    contentEpoch: model.editorContentEpoch,
                    onTextChange: { id, text in
                        model.tabTexts[id] = text
                    },
                    onRun: { id, sql in
                        model.run(id, sql: sql)
                    },
                    onSaveQuery: { id, sql in
                        let suggested = model.document.openTabs.first(where: { $0.id == id })?.title
                        model.beginSaveQuery(sql: sql, suggestedName: suggested)
                    },
                    onRegisterSQLProvider: { host in
                        model.activeSQLProvider = { [weak host] in
                            host?.activeTextView?.activeSQLSnippet()
                        }
                        model.activeEditorInsert = { [weak host] tabID, text in
                            host?.insertText(text, tabID: tabID) ?? false
                        }
                    }
                )
                .frame(minHeight: SexiQLLayout.editorMinHeight)
                .layoutPriority(1)

                if let selected, showResults {
                    ResultsPaneView(tabID: selected)
                        .frame(minHeight: SexiQLLayout.resultsMinHeight)
                }
            }
            .background(.windowBackground)
        }
    }

    private var tabBar: some View {
        HStack(spacing: SexiQLSpace.xxs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SexiQLSpace.xxs) {
                    ForEach(model.document.openTabs) { tab in
                        tabButton(tab)
                            .onDrag {
                                draggingTabID = tab.id
                                return NSItemProvider(object: tab.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: ListReorderDropDelegate(
                                    targetID: tab.id,
                                    draggingID: { draggingTabID },
                                    setDraggingID: { draggingTabID = $0 },
                                    move: { dragged, before in
                                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                                            model.moveTab(id: dragged, before: before)
                                        }
                                    }
                                )
                            )
                    }
                    Color.clear
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [.text],
                            delegate: ListReorderDropDelegate(
                                targetID: nil,
                                draggingID: { draggingTabID },
                                setDraggingID: { draggingTabID = $0 },
                                move: { dragged, before in
                                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                                        model.moveTab(id: dragged, before: before)
                                    }
                                }
                            )
                        )
                }
                .padding(.horizontal, SexiQLSpace.sm)
            }
            Button {
                model.newTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.trailing, SexiQLLayout.panelChromeHorizontal)
            .help("New Query Tab (⌘T)")
        }
        .frame(height: SexiQLLayout.secondaryChromeHeight)
        .background(.bar)
    }

    private func tabButton(_ tab: EditorTabState) -> some View {
        HStack(spacing: SexiQLSpace.sm) {
            if renamingTabID == tab.id {
                TextField("Tab name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(SexiQLType.rowTitle)
                    .frame(minWidth: 80, maxWidth: SexiQLLayout.tabMaxWidth + 40)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(tab.id) }
                    .onExitCommand { cancelRename() }
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused, renamingTabID == tab.id {
                            commitRename(tab.id)
                        }
                    }
            } else {
                Button {
                    model.selectedTabID = tab.id
                } label: {
                    Text(tab.title)
                        .font(SexiQLType.rowTitle)
                        .lineLimit(1)
                        .frame(maxWidth: SexiQLLayout.tabMaxWidth, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        beginRename(tab.id)
                    }
                )
            }

            Button {
                model.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, SexiQLSpace.sm)
        .background {
            if model.selectedTabID == tab.id || renamingTabID == tab.id {
                RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                    .fill(SexiQLColors.selectionFillStrong)
            }
        }
        .contextMenu {
            Button("Rename…") { beginRename(tab.id) }
            Divider()
            Button("Close") { model.closeTab(tab.id) }
            Button("Close Others") { model.closeOtherTabs(keeping: tab.id) }
                .disabled(model.document.openTabs.count < 2)
        }
    }

    private func beginRename(_ tabID: UUID) {
        guard let tab = model.document.openTabs.first(where: { $0.id == tabID }) else { return }
        model.selectedTabID = tabID
        renameDraft = tab.title
        renamingTabID = tabID
        DispatchQueue.main.async {
            renameFieldFocused = true
        }
    }

    private func commitRename(_ tabID: UUID) {
        _ = model.renameTab(tabID, to: renameDraft)
        renamingTabID = nil
        renameFieldFocused = false
    }

    private func cancelRename() {
        renamingTabID = nil
        renameFieldFocused = false
        renameDraft = ""
    }
}



