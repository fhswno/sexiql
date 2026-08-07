import SwiftUI
import SQLUI

struct AIMessageBubble: View {
    let message: AIChatMessage
    var isStreamingMessage: Bool
    var isEditing: Bool
    @Binding var editDraft: String
    var actionsEnabled: Bool
    var onCopy: () -> Void
    var onBeginEdit: () -> Void
    var onCancelEdit: () -> Void
    var onCommitEdit: () -> Void
    var onInsertSQL: (String) -> Void

    @State private var hovering = false
    @State private var copied = false

    private var showActions: Bool {
        hovering || isEditing
    }

    private var isUser: Bool { message.role == .user }
    private var isEmptyAssistant: Bool {
        message.role == .assistant
            && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.xs) {
            HStack(alignment: .center, spacing: SexiQLSpace.sm) {
                roleLabel
                Spacer(minLength: 0)
                if !isEditing {
                    actionBar
                        .opacity(showActions ? 1 : 0.35)
                        .animation(.easeOut(duration: 0.12), value: showActions)
                }
            }

            if isEditing {
                editChrome
            } else if isEmptyAssistant {
                thinkingRow
            } else {
                MarkdownMessageView(
                    text: message.content,
                    isStreaming: isStreamingMessage,
                    showsCodeInsert: !isUser,
                    onInsertSQL: onInsertSQL
                )
            }
        }
        .padding(.horizontal, SexiQLSpace.md)
        .padding(.top, SexiQLSpace.sm)
        .padding(.bottom, SexiQLSpace.md)
        .background {
            RoundedRectangle(cornerRadius: SexiQLRadius.lg, style: .continuous)
                .fill(isUser
                      ? Color.primary.opacity(0.055)
                      : Color.accentColor.opacity(0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: SexiQLRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(isUser ? 0.04 : 0.06), lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .focusable()
        .onKeyPress(.escape) {
            if isEditing {
                onCancelEdit()
                return .handled
            }
            return .ignored
        }
    }

    private var roleLabel: some View {
        HStack(spacing: SexiQLSpace.xs) {
            Image(systemName: isUser ? "person.fill" : "sparkles")
                .font(.system(size: 9, weight: .semibold))
            Text(isUser ? "You" : "AI")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var thinkingRow: some View {
        HStack(spacing: SexiQLSpace.sm) {
            ProgressView()
                .controlSize(.mini)
            Text("Thinking…")
                .font(SexiQLType.rowSubtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            if isUser {
                bubbleIconButton(
                    systemImage: "pencil",
                    help: "Edit message",
                    disabled: !actionsEnabled || isStreamingMessage
                ) {
                    onBeginEdit()
                }
            }
            bubbleIconButton(
                systemImage: copied ? "checkmark" : "doc.on.doc",
                help: copied ? "Copied" : "Copy message",
                disabled: message.content.isEmpty,
                emphasized: copied
            ) {
                onCopy()
                flashCopied()
            }
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(showActions ? 0.06 : 0.03))
        }
    }

    private var editChrome: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.md) {
            TextEditor(text: $editDraft)
                .font(.system(.callout))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72, maxHeight: 180)
                .padding(SexiQLSpace.sm)
                .background {
                    RoundedRectangle(cornerRadius: SexiQLRadius.sm, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: SexiQLRadius.sm, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                }

            HStack(spacing: SexiQLSpace.sm) {
                Text("Saves and regenerates from here")
                    .font(SexiQLType.meta)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button("Cancel", action: onCancelEdit)
                    .keyboardShortcut(.cancelAction)
                Button("Save & regenerate") {
                    onCommitEdit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func bubbleIconButton(
        systemImage: String,
        help: String,
        disabled: Bool = false,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    emphasized
                        ? Color.accentColor
                        : (disabled ? Color.secondary.opacity(0.4) : Color.secondary)
                )
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private func flashCopied() {
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.easeIn(duration: 0.2)) { copied = false }
        }
    }
}
