import SwiftUI
import SQLUI

struct AIPanelHeader: View {
    var modelName: String
    var streaming: Bool
    var canClear: Bool
    var onStop: () -> Void
    var onClear: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: SexiQLSpace.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("AI")
                .font(.callout.weight(.semibold))
            if let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                Text(name)
                    .font(SexiQLType.meta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if streaming {
                Button("Stop", action: onStop)
                    .buttonStyle(.borderless)
                    .font(SexiQLType.rowSubtitle)
                    .help("Stop generating")
            }
            if canClear {
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear conversation")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Close AI panel")
        }
        .padding(.leading, SexiQLLayout.panelChromeHorizontal)
        .padding(.trailing, SexiQLLayout.panelChromeHorizontal)
        .frame(
            maxWidth: .infinity,
            minHeight: SexiQLLayout.secondaryChromeHeight,
            maxHeight: SexiQLLayout.secondaryChromeHeight,
            alignment: .center
        )
        .background(.bar)
    }
}

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
