import SwiftUI
import SQLUI

struct AIPanelEmptyState: View {
    var onExplain: () -> Void
    var onOpenSettings: () -> Void
    var canExplain: Bool

    var body: some View {
        VStack(spacing: SexiQLSpace.lg) {
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("Explain SQL with local AI")
                .font(SexiQLType.emptyTitle)
                .multilineTextAlignment(.center)
            Text("Uses selection when text is highlighted, otherwise the whole tab. Runs on your Mac via Ollama.")
                .font(SexiQLType.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if canExplain {
                Button("Explain current SQL", action: onExplain)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            Button("AI settings…", action: onOpenSettings)
                .buttonStyle(.borderless)
                .font(SexiQLType.rowSubtitle)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SexiQLSpace.xl)
    }
}
