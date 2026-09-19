import SwiftUI
import SQLCore
import SQLDrivers
import SQLImportExport
import SQLUI

struct ImportSheet: View {
    @Environment(WorkspaceModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                destinationSection
                formatSection
                mappingSection
                previewSection
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 660, height: 640)
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

    private var targetProfile: ConnectionProfile? {
        session.profileID.flatMap { id in
            model.document.connections.first(where: { $0.id == id })
        }
    }

    private var destinationSection: some View {
        Section("Destination") {
            LabeledContent("Connection") {
                HStack(spacing: 6) {
                    if let profile = targetProfile {
                        StatusDot(
                            color: model.status(for: profile.id) == .connected
                                ? SexiQLColors.connected
                                : SexiQLColors.disconnected,
                            size: 7
                        )
                        Text(profile.name)
                            .lineLimit(1)
                        if profile.readOnly {
                            Text("Read-only")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.15), in: Capsule(style: .continuous))
                        }
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Target table") {
                Picker("", selection: targetTableBinding) {
                    ForEach(model.schemaTables, id: \.self) { table in
                        Text(table).tag(table)
                    }
                }
                .labelsHidden()
            }
            LabeledContent("First row") {
                Toggle("Is header", isOn: headerBinding)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var formatSection: some View {
        Section("CSV format") {
            HStack(spacing: 20) {
                LabeledContent("Delimiter") {
                    Picker("", selection: delimiterBinding) {
                        ForEach(CSVDelimiterKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                LabeledContent("Quote") {
                    Picker("", selection: quoteBinding) {
                        Text("\"").tag(false)
                        Text("'").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 70)
                }
                LabeledContent("Encoding") {
                    Picker("", selection: encodingBinding) {
                        ForEach(CSVTextEncoding.allCases) { encoding in
                            Text(encoding.displayName).tag(encoding)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
        }
    }

    private var mappingSection: some View {
        Section("Column mapping — table column ← CSV column") {
            if session.tableColumns.isEmpty {
                Text("Select a target table to see its columns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.tableColumns, id: \.self) { tableColumn in
                    LabeledContent(tableColumn) {
                        Picker("", selection: mappingBinding(for: tableColumn)) {
                            Text("— skip —").tag("")
                            ForEach(session.csvColumns, id: \.self) { csvColumn in
                                Text(csvColumn).tag(csvColumn)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            previewTable
        }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 96)
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
            .keyboardShortcut(.cancelAction)
            .pointerCursor()
            Button("Import") {
                Task { await model.runImport() }
            }
            .keyboardShortcut(.defaultAction)
            .pointerCursor()
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
            set: { newValue in
                model.importSession?.hasHeader = newValue
                model.reloadImportSession()
            }
        )
    }

    private var delimiterBinding: Binding<CSVDelimiterKind> {
        Binding(
            get: { session.delimiterKind },
            set: { newValue in
                model.importSession?.dialect.delimiter = newValue.character
                model.reloadImportSession()
            }
        )
    }

    private var quoteBinding: Binding<Bool> {
        Binding(
            get: { session.quoteIsApostrophe },
            set: { newValue in
                model.importSession?.dialect.quote = newValue ? "'" : "\""
                model.reloadImportSession()
            }
        )
    }

    private var encodingBinding: Binding<CSVTextEncoding> {
        Binding(
            get: { session.textEncoding },
            set: { newValue in
                model.importSession?.dialect.encoding = newValue.encoding
                model.reloadImportSession()
            }
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
