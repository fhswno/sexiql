import SwiftUI
import SQLCore
import SQLUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(WorkspaceModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    @State private var sidebarWidth: CGFloat = SexiQLLayout.sidebarIdeal
    @State private var sidebarDragStart: CGFloat?
    @State private var aiPanelWidth: CGFloat = SexiQLLayout.inspectorIdeal + 60
    @State private var aiPanelDragStart: CGFloat?
    @State private var sidebarDividerHover = false
    @State private var aiPanelDividerHover = false

    private let horizontalDividerHeight: CGFloat = 8
    private let editorMinWidth: CGFloat = 420

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    Group {
                        SidebarView()
                            .frame(width: clampedSidebarWidth(totalWidth: geo.size.width))
                        sidebarDivider(totalWidth: geo.size.width)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                EditorAreaView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.aiPanelVisible {
                    Group {
                        aiPanelDivider(totalWidth: geo.size.width)
                        AIPanelView()
                            .frame(width: clampedAIPanelWidth(totalWidth: geo.size.width))
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.sidebarVisible)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.aiPanelVisible)
        }
        .sheet(isPresented: Bindable(model).showingConnectionEditor) {
            ConnectionEditorView(profile: model.editingProfile)
        }
        .sheet(isPresented: Bindable(model).showingSaveQuerySheet) {
            SaveQuerySheet()
        }
        .sheet(isPresented: Bindable(model).showingImportSheet) {
            ImportSheet()
        }
        .fileImporter(
            isPresented: Bindable(model).showingImportFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  let selectedID = model.selectedConnectionID else { return }
            model.prepareImport(from: url, profileID: selectedID)
        }
        .sheet(item: Bindable(model).connectionFailure) { failure in
            ConnectionFailureSheet(failure: failure)
        }
        .sheet(isPresented: Bindable(model).showingSettingsSearch) {
            SettingsSearchSheet()
        }
        .sheet(isPresented: Bindable(model).showingAISetup) {
            AISetupSheet()
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") {}
        } message: {
            Text(model.activeError ?? "")
        }
        .toolbar {
            SexiQLToolbar()
        }
        .onAppear {
            AppIconAppearance.apply(for: model.appearance)
            model.restoreLiveConnectionsIfNeeded()
            if model.showWelcome {
                WelcomeWindow.shared.show(model: model)
            }
        }
        .onChange(of: model.showWelcome) { _, shown in
            if shown {
                WelcomeWindow.shared.show(model: model)
            } else {
                WelcomeWindow.shared.close()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sexiqlSystemAppearanceDidChange)) { _ in
            if model.appearance == .system {
                AppIconAppearance.apply(for: .system)
            }
        }
        .onChange(of: model.appearance) { _, mode in
            AppIconAppearance.apply(for: mode)
        }
        .tint(SexiQLColors.chromeTint(model.document.settings.tintName, scheme: colorScheme))
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: pendingDeleteBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.confirmPendingDelete()
            }
            Button("Cancel", role: .cancel) {
                model.cancelPendingDelete()
            }
        } message: {
            Text("This cannot be undone from the database unless you use Undo immediately.")
        }
        .confirmationDialog(
            "Disconnect \(model.pendingDisconnect?.name ?? "this connection")?",
            isPresented: pendingDisconnectBinding,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                model.confirmPendingDisconnect()
            }
            Button("Cancel", role: .cancel) {
                model.cancelPendingDisconnect()
            }
        } message: {
            Text("The live connection will be closed.")
        }
        .confirmationDialog(
            "Delete \"\(model.pendingDeleteProfile?.name ?? "this connection")\"?",
            isPresented: pendingDeleteProfileBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.confirmPendingDeleteProfile()
            }
            Button("Cancel", role: .cancel) {
                model.cancelPendingDeleteProfile()
            }
        } message: {
            Text("The connection and its saved password will be removed.")
        }
    }

    private var deleteDialogTitle: String {
        let count = model.pendingDeleteRows?.rows.count ?? 0
        return count == 1 ? "Delete this row?" : "Delete \(count) rows?"
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { model.pendingDeleteRows != nil },
            set: { if !$0 { model.cancelPendingDelete() } }
        )
    }

    private var pendingDisconnectBinding: Binding<Bool> {
        Binding(
            get: { model.pendingDisconnect != nil },
            set: { if !$0 { model.cancelPendingDisconnect() } }
        )
    }

    private var pendingDeleteProfileBinding: Binding<Bool> {
        Binding(
            get: { model.pendingDeleteProfile != nil },
            set: { if !$0 { model.cancelPendingDeleteProfile() } }
        )
    }

    // MARK: - Horizontal Split

    private var reservedAIPanelWidth: CGFloat {
        guard model.aiPanelVisible else { return 0 }
        return min(max(aiPanelWidth, SexiQLLayout.inspectorMin + 40), SexiQLLayout.inspectorMax + 80)
    }

    private var reservedSidebarWidth: CGFloat {
        guard model.sidebarVisible else { return 0 }
        return min(max(sidebarWidth, SexiQLLayout.sidebarMin), SexiQLLayout.sidebarMax)
    }

    private func clampedSidebarWidth(totalWidth: CGFloat) -> CGFloat {
        let maxAllowed = max(
            SexiQLLayout.sidebarMin,
            totalWidth - editorMinWidth - horizontalDividerHeight - reservedAIPanelWidth
        )
        return min(max(sidebarWidth, SexiQLLayout.sidebarMin), min(SexiQLLayout.sidebarMax, maxAllowed))
    }

    private func clampedAIPanelWidth(totalWidth: CGFloat) -> CGFloat {
        let maxAllowed = max(
            SexiQLLayout.inspectorMin + 40,
            totalWidth - editorMinWidth - horizontalDividerHeight - reservedSidebarWidth
        )
        return min(max(aiPanelWidth, SexiQLLayout.inspectorMin + 40), min(SexiQLLayout.inspectorMax + 80, maxAllowed))
    }

    private func sidebarDivider(totalWidth: CGFloat) -> some View {
        horizontalDivider(
            hover: $sidebarDividerHover,
            gesture: DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if sidebarDragStart == nil {
                        sidebarDragStart = clampedSidebarWidth(totalWidth: totalWidth)
                    }
                    guard let start = sidebarDragStart else { return }
                    sidebarWidth = start + value.translation.width
                }
                .onEnded { _ in sidebarDragStart = nil }
        )
    }

    private func aiPanelDivider(totalWidth: CGFloat) -> some View {
        horizontalDivider(
            hover: $aiPanelDividerHover,
            gesture: DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if aiPanelDragStart == nil {
                        aiPanelDragStart = clampedAIPanelWidth(totalWidth: totalWidth)
                    }
                    guard let start = aiPanelDragStart else { return }
                    aiPanelWidth = start - value.translation.width
                }
                .onEnded { _ in aiPanelDragStart = nil }
        )
    }

    private func horizontalDivider(
        hover: Binding<Bool>,
        gesture: some Gesture
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(width: 1)
        }
        .frame(width: horizontalDividerHeight)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(hover.wrappedValue ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering in
            hover.wrappedValue = hovering
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .gesture(gesture)
        .accessibilityLabel("Resize panels")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.activeError != nil },
            set: { if !$0 { model.activeError = nil } }
        )
    }
}
