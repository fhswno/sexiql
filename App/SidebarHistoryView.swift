import SwiftUI
import SQLCore
import SQLUI

struct SidebarHistoryView: View {
    @Environment(WorkspaceModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChromeSectionHeader(title: "History")

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
                                .buttonStyle(.plain)
                                .padding(.horizontal, SexiQLSpace.lg)
                                .padding(.vertical, SexiQLSpace.sm)

                                Button {
                                    model.rerunHistory(entry)
                                } label: {
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help("Run in a new tab")
                                .padding(.trailing, SexiQLSpace.md)
                            }
                        }
                    }
                    .padding(.bottom, SexiQLSpace.lg)
                }
            }
        }
    }

    private func historyLabel(_ sql: String) -> String {
        sql.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
