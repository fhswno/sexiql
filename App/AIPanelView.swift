import SwiftUI
import SQLUI

struct AIPanelView: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var draft = ""
    @State private var editingMessageID: UUID?
    @State private var editDraft = ""

    private var tabID: UUID? { model.selectedTabID }
    private var messages: [AIChatMessage] { model.aiMessages(for: tabID) }
    private var streaming: Bool {
        guard let tabID else { return false }
        return model.aiStreamingTabs.contains(tabID)
    }
    private var error: String? {
        tabID.flatMap { model.aiError[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AIPanelHeader(
                modelName: model.ollamaModel,
                streaming: streaming,
                canClear: tabID != nil && !messages.isEmpty && !streaming,
                onStop: {
                    if let tabID { model.cancelAIExplain(tabID) }
                },
                onClear: {
                    if let tabID { model.clearAIChat(tabID) }
                },
                onClose: {
                    model.aiPanelVisible = false
                }
            )
            Divider()
            if messages.isEmpty && error == nil && !streaming {
                AIPanelEmptyState(
                    onExplain: {
                        if let tabID { model.explainWithAI(tabID) }
                    },
                    onOpenSettings: {
                        model.openSettings(focus: .ai)
                    },
                    canExplain: tabID != nil
                )
            } else {
                AIPanelMessageList(
                    messages: messages,
                    streaming: streaming,
                    editingMessageID: editingMessageID,
                    editDraft: $editDraft,
                    onCopy: { copyToPasteboard($0.content) },
                    onBeginEdit: { message in
                        editingMessageID = message.id
                        editDraft = message.content
                    },
                    onCancelEdit: {
                        editingMessageID = nil
                        editDraft = ""
                    },
                    onCommitEdit: { messageID in
                        commitEdit(messageID: messageID)
                    },
                    onInsertSQL: { sql in
                        _ = model.insertSQLIntoActiveEditor(sql)
                    }
                )
            }
            if let error, !error.isEmpty {
                AIPanelErrorBanner(text: error)
            }
            Divider()
            AIPanelComposer(
                draft: $draft,
                isEnabled: tabID != nil && !streaming,
                onSend: send
            )
        }
        .background(.ultraThinMaterial)
    }

    private func commitEdit(messageID: UUID) {
        guard let tabID else { return }
        let text = editDraft
        editingMessageID = nil
        editDraft = ""
        model.editAIMessage(tabID: tabID, messageID: messageID, newText: text)
    }

    private func send() {
        guard let tabID else { return }
        let text = draft
        draft = ""
        model.sendAIFollowUp(tabID, text: text)
    }
}
