import SwiftUI
import SQLCore
import SQLUI

struct SidebarSavedView: View {
    @Environment(WorkspaceModel.self) private var model
    @Binding var renameTarget: SavedQuery?
    @Binding var renameDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChromeSectionHeader(title: "Saved Queries") {
                Button {
                    model.beginSaveQuery()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Save current query")
            }

            if model.document.savedQueries.isEmpty {
                EmptyStateView(
                    title: "No saved queries",
                    subtitle: "Select SQL in the editor, right‑click → Save Query…, or click +.",
                    systemImage: "bookmark",
                    actionTitle: "Save Current Tab"
                ) {
                    model.beginSaveQuery()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SexiQLSpace.xxs) {
                        ForEach(model.document.savedQueries) { query in
                            savedQueryRow(query)
                        }
                    }
                    .padding(.horizontal, SexiQLSpace.md)
                    .padding(.bottom, SexiQLSpace.lg)
                }
            }
        }
    }

    private func savedQueryRow(_ query: SavedQuery) -> some View {
        HStack(spacing: SexiQLSpace.md) {
            Button {
                model.openSavedQuery(query)
            } label: {
                HStack(spacing: SexiQLSpace.md) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                        .frame(width: 18)
                    Text(query.name)
                        .font(SexiQLType.rowTitle)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Open") { model.openSavedQuery(query) }
                Button("Rename…") { beginRename(query) }
                Divider()
                Button("Delete", role: .destructive) { model.deleteSavedQuery(query) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Saved query actions")
        }
        .padding(.horizontal, SexiQLSpace.md)
        .padding(.vertical, 7)
        .contextMenu {
            Button("Open") { model.openSavedQuery(query) }
            Button("Rename…") { beginRename(query) }
            Divider()
            Button("Delete", role: .destructive) { model.deleteSavedQuery(query) }
        }
    }

    private func beginRename(_ query: SavedQuery) {
        renameDraft = query.name
        renameTarget = query
    }
}
