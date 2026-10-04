import SwiftUI

public enum CanvasEdgeGeometry {
    public static func anchors(
        for edge: CanvasEdge,
        tables: [String: CanvasTable],
        compact: Bool = false
    ) -> (start: CGPoint, end: CGPoint)? {
        guard let from = tables[edge.fromTableID],
              let to = tables[edge.toTableID] else {
            return nil
        }
        let fromRow = compact ? 0 : rowIndex(of: edge.fromColumn, in: from)
        let toRow = compact ? 0 : rowIndex(of: edge.toColumn, in: to)
        guard !compact || (fromRow != nil && toRow != nil) else { return nil }

        let fromCenterX = from.position.x + CanvasCardMetrics.cardWidth / 2
        let toCenterX = to.position.x + CanvasCardMetrics.cardWidth / 2
        let fromOnLeft = fromCenterX <= toCenterX
        let isSelfLoop = edge.fromTableID == edge.toTableID

        let startY = compact
            ? from.position.y + CanvasCardMetrics.headerHeight / 2
            : columnCenterY(in: from, row: fromRow!)
        let endY = compact
            ? to.position.y + CanvasCardMetrics.headerHeight / 2
            : columnCenterY(in: to, row: toRow!)

        let start: CGPoint
        let end: CGPoint
        if isSelfLoop {
            start = CGPoint(x: from.position.x, y: startY)
            end = CGPoint(x: from.position.x, y: endY)
        } else {
            start = CGPoint(
                x: fromOnLeft ? from.position.x + CanvasCardMetrics.cardWidth : from.position.x,
                y: startY
            )
            end = CGPoint(
                x: fromOnLeft ? to.position.x : to.position.x + CanvasCardMetrics.cardWidth,
                y: endY
            )
        }
        return (start, end)
    }

    public static func bezier(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        let dx = (end.x - start.x) * 0.45
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + dx, y: start.y),
            control2: CGPoint(x: end.x - dx, y: end.y)
        )
        return path
    }

    public static func selfLoop(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        let reach: CGFloat = 46
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x - reach, y: start.y + (start.y - end.y) * 0.2),
            control2: CGPoint(x: end.x - reach, y: end.y - (start.y - end.y) * 0.2)
        )
        return path
    }

    public static func samplePoints(
        from start: CGPoint,
        to end: CGPoint,
        isLoop: Bool,
        samples: Int = 28
    ) -> [CGPoint] {
        let c1: CGPoint
        let c2: CGPoint
        if isLoop {
            let reach = 46.0
            c1 = CGPoint(x: start.x - reach, y: start.y + (start.y - end.y) * 0.2)
            c2 = CGPoint(x: end.x - reach, y: end.y - (start.y - end.y) * 0.2)
        } else {
            let dx = (end.x - start.x) * 0.45
            c1 = CGPoint(x: start.x + dx, y: start.y)
            c2 = CGPoint(x: end.x - dx, y: end.y)
        }
        var points: [CGPoint] = []
        points.reserveCapacity(samples + 1)
        for step in 0...samples {
            let t = Double(step) / Double(samples)
            let mt = 1 - t
            let x = mt * mt * mt * start.x
                + 3 * mt * mt * t * c1.x
                + 3 * mt * t * t * c2.x
                + t * t * t * end.x
            let y = mt * mt * mt * start.y
                + 3 * mt * mt * t * c1.y
                + 3 * mt * t * t * c2.y
                + t * t * t * end.y
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    static func rowIndex(of column: String, in table: CanvasTable) -> Int? {
        table.columns.firstIndex { $0.name == column }
    }

    static func columnCenterY(in table: CanvasTable, row: Int) -> Double {
        table.position.y
            + CanvasCardMetrics.headerHeight
            + Double(row) * CanvasCardMetrics.rowHeight
            + CanvasCardMetrics.rowHeight / 2
    }


    // MARK: - Notation Glyphs

    public static func crowFootProngs(at tip: CGPoint, toward tail: CGPoint) -> Path {
        let angle = atan2(tail.y - tip.y, tail.x - tip.x)
        let back = CGPoint(x: tip.x - 9 * cos(angle), y: tip.y - 9 * sin(angle))
        let spread: CGFloat = 0.55
        let prongLength: CGFloat = 9
        var path = Path()
        for offsetAngle in [-spread, 0, spread] {
            path.move(to: back)
            path.addLine(to: CGPoint(
                x: back.x + prongLength * cos(angle + offsetAngle),
                y: back.y + prongLength * sin(angle + offsetAngle)
            ))
        }
        return path
    }

    public static func oneTick(at tip: CGPoint, toward tail: CGPoint) -> Path {
        let angle = atan2(tail.y - tip.y, tail.x - tip.x)
        let perpendicular = angle + .pi / 2
        let half: CGFloat = 5
        var path = Path()
        path.move(to: CGPoint(
            x: tip.x - 5 * cos(angle) + half * cos(perpendicular),
            y: tip.y - 5 * sin(angle) + half * sin(perpendicular)
        ))
        path.addLine(to: CGPoint(
            x: tip.x - 5 * cos(angle) - half * cos(perpendicular),
            y: tip.y - 5 * sin(angle) - half * sin(perpendicular)
        ))
        return path
    }
}
