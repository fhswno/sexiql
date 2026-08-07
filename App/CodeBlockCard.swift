import SwiftUI
import SQLUI

struct CodeBlockCard: View {
    let language: String?
    let code: String
    var allowsInsert: Bool = false
    var onInsert: ((String) -> Void)?

    @State private var copied = false
    @State private var inserted = false
    @State private var hovering = false

    private var title: String {
        let lang = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return lang.isEmpty ? "Code" : lang.uppercased()
    }

    private var codeBodyMinHeight: CGFloat {
        let lines = max(code.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return min(CGFloat(lines) * 16 + 16, 220)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SexiQLSpace.sm) {
                Text(title)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                Spacer(minLength: 0)
                if allowsInsert {
                    actionButton(
                        systemImage: inserted ? "checkmark" : "text.insert",
                        help: inserted ? "Inserted" : "Insert into editor",
                        emphasized: inserted
                    ) {
                        onInsert?(code)
                        flashInserted()
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                actionButton(
                    systemImage: copied ? "checkmark" : "doc.on.doc",
                    help: copied ? "Copied" : "Copy code",
                    emphasized: copied
                ) {
                    copyToPasteboard(code)
                    flashCopied()
                }
                .disabled(code.isEmpty)
            }
            .padding(.horizontal, SexiQLSpace.md)
            .padding(.vertical, SexiQLSpace.sm)
            .background(Color.primary.opacity(hovering ? 0.06 : 0.04))

            CodeBlockTextView(code: code)
                .frame(maxWidth: .infinity, minHeight: codeBodyMinHeight, maxHeight: 220, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) code block")
    }

    private func actionButton(
        systemImage: String,
        help: String,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func flashCopied() {
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.2)) { copied = false }
        }
    }

    private func flashInserted() {
        withAnimation(.easeOut(duration: 0.15)) { inserted = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.2)) { inserted = false }
        }
    }
}
