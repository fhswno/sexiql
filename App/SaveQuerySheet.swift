import SwiftUI
import SQLUI

struct SaveQuerySheet: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.xl) {
            Text("Save Query")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            if !model.pendingSaveSQL.isEmpty {
                Text(previewSQL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(SexiQLSpace.md)
                    .background {
                        RoundedRectangle(cornerRadius: SexiQLRadius.sm, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    model.showingSaveQuerySheet = false
                    model.pendingSaveSQL = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.saveQuery(name: name)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(SexiQLSpace.xxl)
        .onAppear {
            name = model.pendingSaveSuggestedName
        }
    }

    private var previewSQL: String {
        let sql = model.pendingSaveSQL
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sql.count <= 160 { return sql }
        return String(sql.prefix(157)) + "…"
    }
}
