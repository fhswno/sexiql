import SwiftUI
import SQLDrivers
import SQLUI

struct ValueInspectorView: View {
    var columnName: String
    var columnType: String
    var value: SQLValue
    var onCopy: () -> Void
    var onEdit: (() -> Void)?
    var onClose: () -> Void

    @State private var showJSON = true

    private var inspectKind: SQLValueInspect.Kind { SQLValueInspect.kind(of: value) }
    private var prettyJSON: String? {
        if case .string(let text) = value {
            return SQLValueInspect.prettyJSON(text)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)

            HStack(spacing: SexiQLSpace.sm) {
                Text(columnName)
                    .font(SexiQLType.rowTitle)
                    .lineLimit(1)
                Text(inspectKind.displayName)
                    .font(SexiQLType.meta)
                    .foregroundStyle(.secondary)
                if !columnType.isEmpty {
                    Text(columnType)
                        .font(SexiQLType.meta)
                        .foregroundStyle(.tertiary)
                }
                Text(SQLValueInspect.sizeLabel(value))
                    .font(SexiQLType.meta)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if prettyJSON != nil {
                    Picker("", selection: $showJSON) {
                        Text("JSON").tag(true)
                        Text("Raw").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .labelsHidden()
                }
                Button("Copy", action: onCopy)
                    .buttonStyle(.borderless)
                    .help("Copy value")
                if let onEdit {
                    Button("Edit", action: onEdit)
                        .buttonStyle(.borderless)
                }
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close (Esc)")
            }
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.vertical, 6)

            ScrollView {
                bodyText
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SexiQLSpace.lg)
                    .padding(.bottom, SexiQLSpace.sm)
            }
            .frame(minHeight: 72, maxHeight: 160)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var bodyText: some View {
        switch value {
        case .null:
            Text("NULL")
                .font(.system(size: 12.5, design: .monospaced))
                .italic()
                .foregroundStyle(.tertiary)
        case .data(let data):
            Text(SQLValueInspect.hexPreview(data))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        case .string(let text):
            Text(showJSON ? (prettyJSON ?? text) : text)
                .font(.system(size: 12.5, design: .monospaced))
        default:
            Text(value.displayString)
                .font(.system(size: 12.5, design: .monospaced))
        }
    }
}
