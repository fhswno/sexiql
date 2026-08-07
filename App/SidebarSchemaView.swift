import SwiftUI
import SQLCore
import SQLDrivers
import SQLUI

struct SidebarSchemaView: View {
    @Environment(WorkspaceModel.self) private var model
    @Binding var showingFileImporter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChromeSectionHeader(title: "Schema") {
                if let selectedID = model.selectedConnectionID,
                   model.status(for: selectedID) == .connected {
                    HStack(spacing: SexiQLSpace.xs) {
                        Button {
                            model.refreshSchema()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh schema")
                        .disabled(model.isSchemaLoading || model.isQueryRunning(on: model.selectedTabID))

                        Button {
                            showingFileImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.caption.weight(.semibold))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .help("Import CSV…")
                    }
                }
            }

            if let selectedID = model.selectedConnectionID,
               let connection = model.document.connections.first(where: { $0.id == selectedID }) {
                if model.status(for: connection.id) == .connected {
                    TextField("Filter tables…", text: Bindable(model).schemaFilter)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, SexiQLSpace.lg)
                        .padding(.bottom, SexiQLSpace.sm)

                    if let err = model.schemaError, !err.isEmpty {
                        Text(err)
                            .font(SexiQLType.rowSubtitle)
                            .foregroundStyle(SexiQLColors.failed)
                            .padding(.horizontal, SexiQLSpace.lg)
                            .padding(.bottom, SexiQLSpace.sm)
                    }

                    if model.isSchemaLoading && model.schemaObjects.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SexiQLSpace.xl)
                    } else if model.filteredSchemaObjects.isEmpty {
                        EmptyStateView(
                            title: model.schemaFilter.isEmpty ? "No tables" : "No matches",
                            subtitle: model.schemaFilter.isEmpty
                                ? "This database has no tables or views yet."
                                : "No tables match “\(model.schemaFilter)”.",
                            systemImage: "tablecells.badge.ellipsis"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(model.filteredSchemaObjects) { object in
                                    schemaObjectRow(object)
                                }
                            }
                            .padding(.horizontal, SexiQLSpace.sm)
                            .padding(.bottom, SexiQLSpace.lg)
                        }
                    }
                } else {
                    EmptyStateView(
                        title: "Not connected",
                        subtitle: "Connect “\(connection.name)” to browse its schema.",
                        systemImage: "bolt.horizontal.circle",
                        actionTitle: "Connect"
                    ) {
                        model.connect(connection)
                    }
                }
            } else {
                EmptyStateView(
                    title: "No connection selected",
                    subtitle: "Pick a connection to inspect tables and views.",
                    systemImage: "cylinder.split.1x2",
                    actionTitle: "Connections"
                ) {
                    model.setSidebarMode(.connections)
                }
            }
        }
    }

    @ViewBuilder
    private func schemaObjectRow(_ object: SchemaObject) -> some View {
        let expanded = model.schemaExpandedIDs.contains(object.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SexiQLSpace.xs) {
                Button {
                    model.toggleSchemaExpand(object)
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 22)
                }
                .buttonStyle(.plain)
                .help(expanded ? "Collapse columns" : "Show columns")

                Button {
                    model.openSchemaObject(object)
                } label: {
                    HStack(spacing: SexiQLSpace.sm) {
                        Image(systemName: object.kind == .view ? "eye" : "tablecells")
                            .foregroundStyle(.secondary)
                        Text(object.displayName)
                            .font(SexiQLType.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open SELECT * LIMIT 1000")
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Open data") { model.openSchemaObject(object) }
                Button("Copy name") {
                    copyToPasteboard(object.displayName)
                }
            }

            if expanded {
                let columns = model.schemaColumnsByID[object.id]
                if let columns {
                    ForEach(columns) { col in
                        HStack(spacing: SexiQLSpace.sm) {
                            Image(systemName: col.isPrimaryKey ? "key.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(col.isPrimaryKey ? Color.accentColor : Color.secondary.opacity(0.4))
                                .frame(width: 14)
                            Text(col.name)
                                .font(SexiQLType.rowSubtitle)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(col.dataType)
                                .font(SexiQLType.meta)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 28)
                        .padding(.vertical, 1)
                    }
                } else {
                    HStack {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Loading columns…")
                            .font(SexiQLType.meta)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 28)
                    .padding(.vertical, SexiQLSpace.xs)
                }
            }
        }
    }
}
