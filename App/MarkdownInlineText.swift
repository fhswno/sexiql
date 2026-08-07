import SwiftUI
import SQLUI

struct MarkdownInlineText: View {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        if let attributed = Self.attributed(raw) {
            Text(attributed)
                .font(.system(.callout))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            MarkdownPlainText(raw)
        }
    }

    static func attributed(_ raw: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let attr = try? AttributedString(markdown: raw, options: options) {
            return styleInlineCode(attr)
        }
        return AttributedString(raw)
    }

    private static func styleInlineCode(_ input: AttributedString) -> AttributedString {
        var result = input
        for run in input.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                let range = run.range
                result[range].font = .system(.callout, design: .monospaced)
                result[range].backgroundColor = Color.primary.opacity(0.08)
            }
        }
        return result
    }
}

struct MarkdownPlainText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.callout))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
