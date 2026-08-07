import SwiftUI

struct ImportSheet: View {
    @Environment(WorkspaceModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mappingArea
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
    }

    private var header: some View {
        HStack {
            Text("Import CSV")
                .font(.headline)
            Spacer()
            Text("\(session.csvRows.count) rows · \(session.csvColumns.count) columns")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var session: ImportSession {
        model.importSession ?? ImportSession(csvColumns: [], csvRows: [], hasHeader: true)
    }

    private var mappingArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Target table")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
                Picker("", selection: targetTableBinding) {
                    ForEach(model.schemaTables, id: \.self) { table in
                        Text(table).tag(table)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
                Toggle("First row is header", isOn: headerBinding)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            Text("Column mapping")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.tableColumns, id: \.self) { tableColumn in
                        HStack(spacing: 8) {
                            Text(tableColumn)
                                .font(.callout)
                                .frame(width: 130, alignment: .leading)
                                .lineLimit(1)
                            Picker("", selection: mappingBinding(for: tableColumn)) {
                                Text("— skip —").tag("")
                                ForEach(session.csvColumns, id: \.self) { csvColumn in
                                    Text(csvColumn).tag(csvColumn)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    if session.tableColumns.isEmpty {
                        Text("Select a target table to see its columns.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(2)
            }

            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            previewTable
        }
        .padding(14)
    }

    private var previewTable: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading) {
                GridRow {
                    Text("#")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(session.csvColumns, id: \.self) { column in
                        Text(column)
                            .font(.caption.weight(.semibold))
                    }
                }
                ForEach(session.previewRows.indices, id: \.self) { rowIndex in
                    GridRow {
                        Text("\(rowIndex + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(session.csvColumns, id: \.self) { column in
                            if let csvIndex = session.csvColumns.firstIndex(of: column) {
                                Text(session.previewRows[rowIndex].value(at: csvIndex))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(height: 110)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let message = session.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if session.inserted > 0 || session.failed > 0 {
                Text("Inserted \(session.inserted) · failed \(session.failed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Cancel") {
                model.showingImportSheet = false
            }
            Button("Import") {
                Task { await model.runImport() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(session.isRunning || session.tableColumns.isEmpty)
        }
        .padding(14)
    }

    private var targetTableBinding: Binding<String> {
        Binding(
            get: { session.targetTable },
            set: { newValue in
                model.importSession?.targetTable = newValue
                Task { await model.loadImportTargetColumns() }
            }
        )
    }

    private var headerBinding: Binding<Bool> {
        Binding(
            get: { session.hasHeader },
            set: { model.importSession?.hasHeader = $0 }
        )
    }

    private func mappingBinding(for tableColumn: String) -> Binding<String> {
        Binding(
            get: { session.mapping[tableColumn] ?? "" },
            set: { model.importSession?.mapping[tableColumn] = $0 }
        )
    }
}

private extension Array where Element == String {
    func value(at index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }
}
