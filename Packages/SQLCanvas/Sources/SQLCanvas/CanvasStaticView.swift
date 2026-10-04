import SwiftUI

public struct CanvasStaticView: View {
    public let tables: [CanvasTable]
    public let edges: [CanvasEdge]
    public let scale: CGFloat
    public let contentBounds: CGRect
    public let padding: CGFloat

    public init(
        tables: [CanvasTable],
        edges: [CanvasEdge],
        scale: CGFloat,
        contentBounds: CGRect,
        padding: CGFloat = 40
    ) {
        self.tables = tables
        self.edges = edges
        self.scale = scale
        self.contentBounds = contentBounds
        self.padding = padding
    }

    private var tablesByID: [String: CanvasTable] {
        Dictionary(tables.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var exportOffset: CGSize {
        CGSize(
            width: padding - contentBounds.minX * scale,
            height: padding - contentBounds.minY * scale
        )
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            CanvasEdgeLayer(
                edges: edges,
                tables: tablesByID,
                scale: scale,
                offset: exportOffset,
                selectedEdgeID: nil,
                selectedTableID: nil,
                highlightedTableIDs: []
            )
            ForEach(tables) { table in
                let width = CanvasCardMetrics.cardWidth * scale
                let height = CanvasCardMetrics.tableHeight(columnCount: table.columns.count) * scale
                CanvasTableCard(table: table)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .offset(
                        x: exportOffset.width + table.position.x * scale,
                        y: exportOffset.height + table.position.y * scale
                    )
            }
        }
        .frame(
            width: contentBounds.width * scale + padding * 2,
            height: contentBounds.height * scale + padding * 2,
            alignment: .topLeading
        )
    }
}
