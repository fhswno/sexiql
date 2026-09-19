import SwiftUI
import SQLCore
import SQLUI

struct SidebarHistoryView: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var showingClearConfirm = false
    @State private var clearHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChromeSectionHeader(title: "History") {
                if !model.document.history.isEmpty {
                    Button {
                        showingClearConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.caption2)
                            Text("Clear History")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(clearHover ? SexiQLColors.failed : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (clearHover ? SexiQLColors.failed.opacity(0.15) : Color.secondary.opacity(0.12)),
                            in: Capsule(style: .continuous)
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain).pointerCursor()
                    .onHover { hovering in
                        clearHover = hovering
                    }
                    .help("Clear all history")
                }
            }

            TextField("Search history…", text: Binding(
                get: { model.historySearch },
                set: { model.historySearch = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.bottom, SexiQLSpace.sm)

            if model.filteredHistory.isEmpty {
                EmptyStateView(
                    title: "No history yet",
                    subtitle: "Queries you run will show up here.",
                    systemImage: "clock"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.filteredHistory) { entry in
                            HStack(spacing: SexiQLSpace.sm) {
                                Button {
                                    model.loadHistoryIntoEditor(entry)
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(historyLabel(entry.sql))
                                            .font(SexiQLType.rowSubtitle)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: SexiQLSpace.xs) {
                                            Text(entry.connectionName ?? "any")
                                                .font(SexiQLType.meta)
                                                .foregroundStyle(.secondary)
                                            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                                                .font(SexiQLType.meta)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).pointerCursor()
                                .padding(.horizontal, SexiQLSpace.lg)
                                .padding(.vertical, SexiQLSpace.sm)

                                Button {
                                    model.rerunHistory(entry)
                                } label: {
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain).pointerCursor()
                                .help("Run in a new tab")
                                .padding(.trailing, SexiQLSpace.md)
                            }
                            .contextMenu {
                                Button("Run in a new tab") {
                                    model.rerunHistory(entry)
                                }
                                Button("Load into editor") {
                                    model.loadHistoryIntoEditor(entry)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    model.deleteHistory(entry)
                                }
                            }
                        }
                    }
                    .padding(.bottom, SexiQLSpace.lg)
                }
            }
        }
        .confirmationDialog(
            "Clear all query history?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                model.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func historyLabel(_ sql: String) -> String {
        sql.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
