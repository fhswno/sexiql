import SwiftUI
import SQLCanvas

struct VirtualRelationshipSheet: View {
    let sourceTableName: String
    let sourceColumnName: String
    let tables: [CanvasTable]
    let onCancel: () -> Void
    let onSave: (_ targetTableID: String, _ targetColumn: String) -> Void

    @State private var targetTableID: String = ""
    @State private var targetColumn: String = ""

    private var targetColumns: [CanvasColumn] {
        tables.first { $0.id == targetTableID }?.columns ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Virtual Relationship")
                .font(.headline)
            Text("A local annotation only — nothing is written to the database.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("From") {
                Text("\(sourceTableName).\(sourceColumnName)")
                    .font(.system(size: 12).monospaced())
            }

            LabeledContent("To table") {
                Picker("", selection: $targetTableID) {
                    ForEach(tables) { table in
                        Text(table.name).tag(table.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            LabeledContent("To column") {
                Picker("", selection: $targetColumn) {
                    ForEach(targetColumns) { column in
                        Text(column.name).tag(column.name)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Relationship") {
                    onSave(targetTableID, targetColumn)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(targetTableID.isEmpty || targetColumn.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if targetTableID.isEmpty, let first = tables.first {
                targetTableID = first.id
                targetColumn = first.columns.first?.name ?? ""
            }
        }
        .onChange(of: targetTableID) { _, _ in
            targetColumn = targetColumns.first?.name ?? ""
        }
    }
}
