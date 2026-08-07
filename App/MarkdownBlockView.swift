import SQLCore
import SwiftUI
import SQLUI

struct MarkdownBlockView: View {
    let block: ChatMarkdownBlock
    var isStreaming: Bool = false
    var showsCodeInsert: Bool = true
    var onInsertSQL: ((String) -> Void)?

    var body: some View {
        switch block {
        case .paragraph(let raw):
            MarkdownInlineText(raw)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let ordered, let items):
            MarkdownListView(ordered: ordered, items: items)
        case .code(let language, let code):
            CodeBlockCard(
                language: language,
                code: code,
                allowsInsert: showsCodeInsert
                    && !isStreaming
                    && ChatMarkdownParser.isSQLInsertable(language: language, code: code),
                onInsert: onInsertSQL
            )
        }
    }
}
