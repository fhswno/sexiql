import SQLCore
import SwiftUI
import SQLUI

struct MarkdownMessageView: View {
    let text: String
    var isStreaming: Bool = false
    var showsCodeInsert: Bool = true
    var onInsertSQL: ((String) -> Void)?

    private var blocks: [ChatMarkdownBlock] {
        ChatMarkdownParser.parse(text)
    }

    var body: some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else if blocks.isEmpty {
            MarkdownPlainText(text)
        } else {
            VStack(alignment: .leading, spacing: SexiQLSpace.md) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(
                        block: block,
                        isStreaming: isStreaming,
                        showsCodeInsert: showsCodeInsert,
                        onInsertSQL: onInsertSQL
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
