import SwiftUI
import SQLCore
import SQLUI

struct ContentView: View {
    @Environment(WorkspaceModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HSplitView {
            if model.sidebarVisible {
                SidebarView()
                    .frame(
                        minWidth: SexiQLLayout.sidebarMin,
                        idealWidth: SexiQLLayout.sidebarIdeal,
                        maxWidth: SexiQLLayout.sidebarMax
                    )
            }

            EditorAreaView()
                .frame(minWidth: 420)

            if model.aiPanelVisible {
                AIPanelView()
                    .frame(
                        minWidth: SexiQLLayout.inspectorMin + 40,
                        idealWidth: SexiQLLayout.inspectorIdeal + 60,
                        maxWidth: SexiQLLayout.inspectorMax + 80
                    )
            }
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.activeError != nil },
            set: { if !$0 { model.activeError = nil } }
        )
    }
}
