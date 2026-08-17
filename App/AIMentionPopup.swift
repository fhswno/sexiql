import SwiftUI
import SQLEditor
import SQLUI

struct AIMentionPopup: View {
    var items: [SQLCompletionItem]
    var selectedIndex: Int
    var emptyMessage: String
    var onPick: (SQLCompletionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) { offset, item in
                    Button {
                        onPick(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.kind == .view ? "eye" : "tablecells")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(item.label)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(offset == selectedIndex ? Color.accentColor : Color.clear)
                        .foregroundStyle(offset == selectedIndex ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 260)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }
}
