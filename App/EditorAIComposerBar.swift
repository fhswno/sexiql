import SwiftUI
import AppKit
import SQLCore
import SQLEditor
import SQLUI

struct EditorAIComposerBar: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var mentionIndex = 0
    @State private var caret: Int?

    private static let promptLimit = 8000

    private var mentionToken: AIMentionToken? {
        AIMention.tokenAtCaret(in: model.editorAIPrompt, utf16Offset: model.editorAIPrompt.utf16.count)
    }

    private var mentionItems: [SQLCompletionItem] {
        guard let mentionToken else { return [] }
        return model.aiMentionItems(prefix: mentionToken.filterPrefix)
    }

    private var mentionActive: Bool {
        mentionToken != nil && !model.editorAIBusy
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: SexiQLSpace.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: model.editorAIBusy)
                    .padding(.top, 4)

                if model.editorAIBusy {
                    Text(model.editorAIStatus ?? "Generating…")
                        .font(SexiQLType.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                    Button("Stop") {
                        model.cancelEditorAI()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        AIComposerTextView(
                            text: cappedPrompt,
                            placeholder: "Ask for SQL… (@table)",
                            isEnabled: true,
                            onSubmit: submit,
                            mentionActive: mentionActive,
                            mentionCount: mentionItems.count,
                            mentionIndex: $mentionIndex,
                            caret: $caret,
                            validatedMentionKeys: model.aiValidatedMentionKeys(),
                            onPickMention: pickMention,
                            autoFocus: true
                        )
                        .frame(height: model.editorAIPrompt.contains("\n") ? 66 : 22)
                        if mentionActive {
                            AIMentionPopup(
                                items: mentionItems,
                                selectedIndex: mentionIndex,
                                emptyMessage: model.aiMentionEmptyMessage(prefix: mentionToken?.filterPrefix ?? ""),
                                onPick: insertMention
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                                )
                            )
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: mentionActive)
                    Button("Generate") {
                        model.submitEditorAIGenerate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.editorAIPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        model.dismissEditorAIComposer()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Close (Esc)")
                }
            }
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.vertical, 10)
            .background(.bar)

            if let status = model.editorAIStatus, !model.editorAIBusy, status != "Generating…", status != "Fixing…" {
                Text(status)
                    .font(SexiQLType.meta)
                    .foregroundStyle(status.hasPrefix("Prompt limited") ? .secondary : SexiQLColors.failed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SexiQLSpace.lg)
                    .padding(.bottom, 8)
                    .background(.bar)
            }

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
        }
        .onChange(of: mentionToken?.filterPrefix) { _, _ in
            mentionIndex = 0
        }
        .onExitCommand {
            if mentionActive {
                dismissMention()
            } else {
                model.dismissEditorAIComposer()
            }
        }
    }

    private var cappedPrompt: Binding<String> {
        Binding(
            get: { model.editorAIPrompt },
            set: { newValue in
                if newValue.count > Self.promptLimit {
                    model.editorAIPrompt = String(newValue.prefix(Self.promptLimit))
                    model.editorAIStatus = "Prompt limited to 8,000 characters."
                } else {
                    model.editorAIPrompt = newValue
                    if model.editorAIStatus == "Prompt limited to 8,000 characters." {
                        model.editorAIStatus = nil
                    }
                }
            }
        )
    }

    private func submit() {
        if mentionActive {
            pickMention()
            return
        }
        model.submitEditorAIGenerate()
    }

    private func pickMention() {
        guard mentionItems.indices.contains(mentionIndex) else { return }
        insertMention(mentionItems[mentionIndex])
    }

    private func insertMention(_ item: SQLCompletionItem) {
        guard let token = mentionToken else { return }
        let ns = model.editorAIPrompt as NSString
        let range = NSRange(location: token.utf16Range.lowerBound, length: token.utf16Range.count)
        guard NSMaxRange(range) <= ns.length else { return }
        let replacement = "@\(item.insertText) "
        model.editorAIPrompt = ns.replacingCharacters(in: range, with: replacement)
        caret = range.location + (replacement as NSString).length
        model.prefetchMention(item)
        mentionIndex = 0
    }

    private func dismissMention() {
        if model.editorAIPrompt.hasSuffix("@") {
            model.editorAIPrompt.removeLast()
        }
        mentionIndex = 0
    }
}
