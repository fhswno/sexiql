import SwiftUI
import SQLUI

struct AIPanelMessageList: View {
    var messages: [AIChatMessage]
    var streaming: Bool
    var editingMessageID: UUID?
    @Binding var editDraft: String
    var onCopy: (AIChatMessage) -> Void
    var onBeginEdit: (AIChatMessage) -> Void
    var onCancelEdit: () -> Void
    var onCommitEdit: (UUID) -> Void
    var onInsertSQL: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SexiQLSpace.lg) {
                    ForEach(messages) { message in
                        AIMessageBubble(
                            message: message,
                            isStreamingMessage: streaming
                                && message.role == .assistant
                                && message.id == messages.last?.id,
                            isEditing: editingMessageID == message.id,
                            editDraft: $editDraft,
                            actionsEnabled: !streaming,
                            onCopy: { onCopy(message) },
                            onBeginEdit: { onBeginEdit(message) },
                            onCancelEdit: onCancelEdit,
                            onCommitEdit: { onCommitEdit(message.id) },
                            onInsertSQL: onInsertSQL
                        )
                        .id(message.id)
                    }
                    if streaming {
                        HStack(spacing: SexiQLSpace.sm) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating…")
                                .font(SexiQLType.meta)
                                .foregroundStyle(.secondary)
                        }
                        .id("ai-streaming")
                        .padding(.leading, SexiQLSpace.xs)
                    }
                }
                .padding(SexiQLSpace.lg)
            }
            .onChange(of: messages.last?.content) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: streaming) { _, _ in
                scrollToBottom(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                if streaming {
                    proxy.scrollTo("ai-streaming", anchor: .bottom)
                } else if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}
