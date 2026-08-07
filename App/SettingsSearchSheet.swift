import SwiftUI
import SQLUI

struct SettingsSearchSheet: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var results: [SettingsSearchItem] {
        SettingsSearchIndex.matches(for: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search settings (e.g. theme)", text: $query)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { openFirst() }
            }
            .padding(14)
            Divider()
            List(results) { item in
                Button {
                    model.applySettingsSearchItem(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body.weight(.medium))
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.section.title)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Text("Return opens the selected setting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") {
                    model.showingSettingsSearch = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 380)
        .onAppear {
            fieldFocused = true
        }
    }

    private func openFirst() {
        if let first = results.first {
            model.applySettingsSearchItem(first)
        }
    }
}

