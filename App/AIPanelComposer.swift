import SwiftUI
import SQLCore
import SQLEditor
import SQLUI

struct AIPanelComposer: View {
    @Environment(WorkspaceModel.self) private var model
    @Binding var draft: String
    var isEnabled: Bool
    var onSend: () -> Void
    @State private var mentionIndex = 0
    @State private var caret: Int?

    private var canSend: Bool {
        isEnabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mentionToken: AIMentionToken? {
        AIMention.tokenAtCaret(in: draft, utf16Offset: draft.utf16.count)
    }

    private var mentionItems: [SQLCompletionItem] {
        guard let mentionToken else { return [] }
        return model.aiMentionItems(prefix: mentionToken.filterPrefix)
    }

    private var mentionActive: Bool {
        mentionToken != nil && isEnabled
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: SexiQLSpace.sm) {
            VStack(alignment: .leading, spacing: 2) {
                if mentionActive {
                    AIMentionPopup(
                        items: mentionItems,
                        selectedIndex: mentionIndex,
                        emptyMessage: model.aiMentionEmptyMessage(prefix: mentionToken?.filterPrefix ?? ""),
                        onPick: insertMention
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom))
                        )
                    )
                }
                AIComposerTextView(
                    text: $draft,
                    placeholder: "Ask a follow-up… (@table)",
                    isEnabled: isEnabled,
                    onSubmit: submit,
                    mentionActive: mentionActive,
                    mentionCount: mentionItems.count,
                    mentionIndex: $mentionIndex,
                    caret: $caret,
                    validatedMentionKeys: model.aiValidatedMentionKeys(),
                    onPickMention: pickMention
                )
                .frame(height: draft.contains("\n") ? 66 : 22)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: mentionActive)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend && !mentionActive)
            .help("Send (Return). Shift+Return for newline.")
        }
        .padding(.horizontal, SexiQLSpace.lg)
        .padding(.vertical, SexiQLSpace.md)
        .onChange(of: mentionToken?.filterPrefix) { _, _ in
            mentionIndex = 0
        }
    }

    private func submit() {
        if mentionActive {
            pickMention()
            return
        }
        onSend()
    }

    private func pickMention() {
        guard mentionItems.indices.contains(mentionIndex) else { return }
        insertMention(mentionItems[mentionIndex])
    }

    private func insertMention(_ item: SQLCompletionItem) {
        guard let token = mentionToken else { return }
        let ns = draft as NSString
        let range = NSRange(location: token.utf16Range.lowerBound, length: token.utf16Range.count)
        guard NSMaxRange(range) <= ns.length else { return }
        let replacement = "@\(item.insertText) "
        draft = ns.replacingCharacters(in: range, with: replacement)
        caret = range.location + (replacement as NSString).length
        model.prefetchMention(item)
        mentionIndex = 0
    }
}
