import SwiftUI
import SQLCore
import SQLDrivers
import SQLUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var showingFileImporter = false
    @State private var renameTarget: SavedQuery?
    @State private var renameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarModePicker(
                modes: SidebarMode.allCases.map { ($0, $0.title, $0.systemImage) },
                selection: sidebarModeBinding
            )

            Divider()

            Group {
                switch model.sidebarMode {
                case .connections:
                    SidebarConnectionsView()
                case .schema:
                    SidebarSchemaView(showingFileImporter: $showingFileImporter)
                case .saved:
                    SidebarSavedView(
                        renameTarget: $renameTarget,
                        renameDraft: $renameDraft
                    )
                case .history:
                    SidebarHistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.ultraThinMaterial)
        .sheet(item: $renameTarget) { query in
            VStack(spacing: SexiQLSpace.xl) {
                Text("Rename Saved Query")
                    .font(.headline)
                TextField("Name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                HStack {
                    Spacer()
                    Button("Cancel") { renameTarget = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Rename") {
                        model.renameSavedQuery(query, to: renameDraft)
                        renameTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(SexiQLSpace.xxl)
            .onAppear { renameDraft = query.name }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  let selectedID = model.selectedConnectionID else { return }
            model.prepareImport(from: url, profileID: selectedID)
        }
    }

    private var sidebarModeBinding: Binding<SidebarMode> {
        Binding(
            get: { model.sidebarMode },
            set: { model.setSidebarMode($0) }
        )
    }
}
