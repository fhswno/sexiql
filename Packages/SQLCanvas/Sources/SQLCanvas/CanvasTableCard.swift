import SwiftUI

public struct CanvasTableCard: View {
    public let table: CanvasTable
    public var compact: Bool = false
    public var onAddVirtualRelationship: ((String) -> Void)?

    public init(
        table: CanvasTable,
        compact: Bool = false,
        onAddVirtualRelationship: ((String) -> Void)? = nil
    ) {
        self.table = table
        self.compact = compact
        self.onAddVirtualRelationship = onAddVirtualRelationship
    }

    public var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var compactBody: some View {
        header
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }

    private var fullBody: some View {
        VStack(spacing: 0) {
            header
            ForEach(table.columns) { column in
                row(column)
                Divider().opacity(0.35)
            }
        }
        .frame(width: CanvasCardMetrics.cardWidth, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 7, y: 2)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tablecells")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(table.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let schema = table.schema, !schema.isEmpty {
                Text(schema)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
            if compact {
                Text("\(table.columns.count)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: compact ? nil : CanvasCardMetrics.cardWidth, height: CanvasCardMetrics.headerHeight)
        .background(Color.primary.opacity(0.06))
    }

    private func row(_ column: CanvasColumn) -> some View {
        HStack(spacing: 5) {
            keyIcons(column)
            Text(column.name)
                .font(.system(size: 11, weight: column.isPrimaryKey ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(column.dataType)
                .font(.system(size: 10).monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if column.isNullable, !column.isPrimaryKey {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: CanvasCardMetrics.rowHeight)
        .contentShape(Rectangle())
        .contextMenu {
            if onAddVirtualRelationship != nil {
                Button("Add Virtual Relationship from \(column.name)…") {
                    onAddVirtualRelationship?(column.name)
                }
            }
        }
    }


    @ViewBuilder
    private func keyIcons(_ column: CanvasColumn) -> some View {
        if column.isPrimaryKey {
            Image(systemName: "key.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .help("Primary key")
        } else if column.isForeignKey {
            Image(systemName: "link")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .help("Foreign key")
        }
    }
}
