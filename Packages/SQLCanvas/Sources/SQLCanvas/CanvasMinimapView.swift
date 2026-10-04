import SwiftUI

public struct CanvasMinimapView: View {
    public let tables: [CanvasTable]
    public let contentBounds: CGRect
    public let offset: CGSize
    public let scale: CGFloat
    public let viewportSize: CGSize
    public let selectedTableIDs: Set<String>
    public var onPan: (CGPoint) -> Void

    public init(
        tables: [CanvasTable],
        contentBounds: CGRect,
        offset: CGSize,
        scale: CGFloat,
        viewportSize: CGSize,
        selectedTableIDs: Set<String>,
        onPan: @escaping (CGPoint) -> Void
    ) {
        self.tables = tables
        self.contentBounds = contentBounds
        self.offset = offset
        self.scale = scale
        self.viewportSize = viewportSize
        self.selectedTableIDs = selectedTableIDs
        self.onPan = onPan
    }

    private var mapSize: CGSize { CGSize(width: 180, height: 120) }
    private var mapPadding: CGFloat { 10 }

    private var effectiveBounds: CGRect {
        let viewportWorld = viewportWorldRect
        var effective = contentBounds
        if viewportWorld.width > 0, viewportWorld.height > 0 {
            effective = effective.union(viewportWorld)
        }
        return effective
    }

    private var viewportWorldRect: CGRect {
        let safeScale = max(scale, 0.001)
        return CGRect(
            x: -offset.width / safeScale,
            y: -offset.height / safeScale,
            width: viewportSize.width / safeScale,
            height: viewportSize.height / safeScale
        )
    }

    private func transform(for size: CGSize) -> (scale: CGFloat, center: CGPoint, bounds: CGRect) {
        let bounds = effectiveBounds
        let safeBounds = bounds.width > 0 && bounds.height > 0
            ? bounds
            : CGRect(x: 0, y: 0, width: 1, height: 1)
        let s = min(
            (size.width - mapPadding * 2) / CGFloat(safeBounds.width),
            (size.height - mapPadding * 2) / CGFloat(safeBounds.height)
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return (s, center, safeBounds)
    }

    private func worldPoint(at location: CGPoint, in size: CGSize) -> CGPoint {
        let (s, center, bounds) = transform(for: size)
        return CGPoint(
            x: bounds.minX + (location.x - center.x) / max(s, 0.0001),
            y: bounds.minY + (location.y - center.y) / max(s, 0.0001)
        )
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let (s, center, bounds) = transform(for: size)

            ZStack {
                Rectangle().fill(Color.primary.opacity(0.03))
                ForEach(tables) { table in
                    let tableHeight = CanvasCardMetrics.tableHeight(columnCount: table.columns.count)
                    let rect = CGRect(
                        x: center.x + (table.position.x + CanvasCardMetrics.cardWidth / 2 - bounds.midX) * s
                            - (CanvasCardMetrics.cardWidth * s) / 2,
                        y: center.y + (table.position.y + tableHeight / 2 - bounds.midY) * s
                            - (tableHeight * s) / 2,
                        width: max(CanvasCardMetrics.cardWidth * s, 3),
                        height: max(tableHeight * s, 2.5)
                    )
                    let isSelected = selectedTableIDs.contains(table.id)
                    miniCard(rect: rect, selected: isSelected)
                }

                let viewportRect = worldToMap(viewportWorldRect, s: s, center: center, bounds: bounds)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.06))
                    .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1.5))
                    .frame(width: max(viewportRect.width, 2), height: max(viewportRect.height, 2))
                    .position(x: viewportRect.midX, y: viewportRect.midY)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let world = worldPoint(at: value.location, in: size)
                        onPan(world)
                    }
            )
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func contextIndependentCard(rect: CGRect, selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.32))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func miniCard(rect: CGRect, selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.32))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func worldToMap(_ rect: CGRect, s: CGFloat, center: CGPoint, bounds: CGRect) -> CGRect {
        CGRect(
            x: center.x + (rect.minX - bounds.midX) * s,
            y: center.y + (rect.minY - bounds.midY) * s,
            width: rect.width * s,
            height: rect.height * s
        )
    }
}
