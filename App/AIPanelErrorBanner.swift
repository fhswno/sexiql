import SwiftUI
import SQLUI

struct AIPanelErrorBanner: View {
    var text: String

    var body: some View {
        Text(text)
            .font(SexiQLType.rowSubtitle)
            .foregroundStyle(SexiQLColors.failed)
            .textSelection(.enabled)
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.vertical, SexiQLSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
