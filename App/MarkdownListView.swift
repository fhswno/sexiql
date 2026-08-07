import SwiftUI
import SQLUI

struct MarkdownListView: View {
    var ordered: Bool
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: SexiQLSpace.sm) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(SexiQLType.rowSubtitle.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: ordered ? 18 : 10, alignment: .trailing)
                    MarkdownInlineText(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
