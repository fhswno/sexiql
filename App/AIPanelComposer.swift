import SwiftUI
import SQLUI

struct AIPanelComposer: View {
    @Binding var draft: String
    var isEnabled: Bool
    var onSend: () -> Void

    private var canSend: Bool {
        isEnabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: SexiQLSpace.sm) {
            AIComposerTextView(
                text: $draft,
                placeholder: "Ask a follow-up…",
                isEnabled: isEnabled,
                onSubmit: onSend
            )
            .frame(minHeight: 22, maxHeight: 96)
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
            .help("Send (Return). Shift+Return for newline.")
        }
        .padding(.horizontal, SexiQLSpace.lg)
        .padding(.vertical, SexiQLSpace.md)
    }
}
