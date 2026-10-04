import SwiftUI

public enum CanvasEdgeNotation {
    case labels
    case crowFoot
}

public struct CanvasEdgeLayer: View {
    public let edges: [CanvasEdge]
    public let tables: [String: CanvasTable]
    public let scale: CGFloat
    public let offset: CGSize
    public let selectedEdgeID: String?
    public let selectedTableID: String?
    public let selectedTableIDs: Set<String>
    public let highlightedTableIDs: Set<String>
    public var filteredOutTableIDs: Set<String> = []
    public var hoveredTableID: String? = nil
    public var hiddenTableIDs: Set<String> = []
    public var compact: Bool = false
    public var notation: CanvasEdgeNotation = .labels
    public var narrationTableIDs: Set<String>? = []

    public init(
        edges: [CanvasEdge],
        tables: [String: CanvasTable],
        scale: CGFloat,
        offset: CGSize,
        selectedEdgeID: String?,
        selectedTableID: String?,
        selectedTableIDs: Set<String> = [],
        highlightedTableIDs: Set<String>,
        filteredOutTableIDs: Set<String> = [],
        hoveredTableID: String? = nil,
        hiddenTableIDs: Set<String> = [],
        compact: Bool = false,
        notation: CanvasEdgeNotation = .labels,
        narrationTableIDs: Set<String>? = []
    ) {
        self.edges = edges
        self.tables = tables
        self.scale = scale
        self.offset = offset
        self.selectedEdgeID = selectedEdgeID
        self.selectedTableID = selectedTableID
        self.selectedTableIDs = selectedTableIDs
        self.highlightedTableIDs = highlightedTableIDs
        self.filteredOutTableIDs = filteredOutTableIDs
        self.hoveredTableID = hoveredTableID
        self.hiddenTableIDs = hiddenTableIDs
        self.compact = compact
        self.notation = notation
        self.narrationTableIDs = narrationTableIDs
    }

    public var body: some View {
        Canvas { context, _ in
            for edge in edges {
                if hiddenTableIDs.contains(edge.fromTableID) || hiddenTableIDs.contains(edge.toTableID) {
                    continue
                }
                guard let anchors = CanvasEdgeGeometry.anchors(
                    for: edge,
                    tables: tables,
                    compact: compact
                ) else { continue }
                let start = toScreen(anchors.start)
                let end = toScreen(anchors.end)

                let style = style(for: edge)
                var path: Path
                if edge.fromTableID == edge.toTableID {
                    path = CanvasEdgeGeometry.selfLoop(from: start, to: end)
                } else {
                    path = CanvasEdgeGeometry.bezier(from: start, to: end)
                }
                context.stroke(
                    path,
                    with: .color(style.color),
                    style: StrokeStyle(
                        lineWidth: style.lineWidth,
                        lineCap: .round,
                        dash: edge.isVirtual ? [5, 4] : []
                    )
                )

                if notation == .crowFoot {
                    let prongs = CanvasEdgeGeometry.crowFootProngs(at: start, toward: end)
                    context.stroke(prongs, with: .color(style.color), lineWidth: style.lineWidth)
                    let tick = CanvasEdgeGeometry.oneTick(at: end, toward: start)
                    context.stroke(tick, with: .color(style.color), lineWidth: style.lineWidth)
                } else {
                    drawArrow(context: context, at: end, toward: start, color: style.color, width: style.lineWidth)
                    drawCardinality(context: context, text: "N", at: start, color: style.color)
                    drawCardinality(context: context, text: "1", at: end, color: style.color)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct EdgeStyle {
        let color: Color
        let lineWidth: CGFloat
    }

    private func style(for edge: CanvasEdge) -> EdgeStyle {
        if let narration = narrationTableIDs {
            let touches = narration.contains(edge.fromTableID) && narration.contains(edge.toTableID)
            return touches
                ? EdgeStyle(color: .accentColor.opacity(0.95), lineWidth: 2.2)
                : EdgeStyle(color: .secondary.opacity(0.08), lineWidth: 1.2)
        }
        if edge.id == selectedEdgeID {
            return EdgeStyle(color: .accentColor, lineWidth: 2.4)
        }
        if isFilteredOut(edge) {
            return EdgeStyle(color: .secondary.opacity(0.08), lineWidth: 1.2)
        }
        let dimmed = selectedEdgeID != nil
        return EdgeStyle(color: .secondary.opacity(dimmed ? 0.2 : 0.55), lineWidth: 1.6)
    }

    private func isFilteredOut(_ edge: CanvasEdge) -> Bool {
        guard !filteredOutTableIDs.isEmpty else { return false }
        return filteredOutTableIDs.contains(edge.fromTableID)
            || filteredOutTableIDs.contains(edge.toTableID)
    }

    private func toScreen(_ world: CGPoint) -> CGPoint {
        CGPoint(
            x: world.x * scale + offset.width,
            y: world.y * scale + offset.height
        )
    }

    private func drawArrow(context: GraphicsContext, at tip: CGPoint, toward tail: CGPoint, color: Color, width: CGFloat) {
        let angle = atan2(tail.y - tip.y, tail.x - tip.x)
        let length = 7.0 + width * 1.5
        let spread: CGFloat = 0.42
        let a = CGPoint(
            x: tip.x - length * cos(angle - spread),
            y: tip.y - length * sin(angle - spread)
        )
        let b = CGPoint(
            x: tip.x - length * cos(angle + spread),
            y: tip.y - length * sin(angle + spread)
        )
        var path = Path()
        path.move(to: tip)
        path.addLine(to: a)
        path.addLine(to: b)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }


    private func drawCardinality(context: GraphicsContext, text: String, at point: CGPoint, color: Color) {
        let resolved = context.resolve(
            Text(text)
                .font(.system(size: 9, weight: .bold).monospaced())
                .foregroundColor(color)
        )
        context.draw(resolved, at: CGPoint(x: point.x, y: point.y - 9))
    }
}
