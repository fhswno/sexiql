import Foundation
import CoreGraphics

public enum CanvasCanvasInteractionMath {
    public static func isFrameVisible(
        position: CanvasPoint,
        cardWidth: Double,
        cardHeight: Double,
        scale: CGFloat,
        offset: CGSize,
        viewport: CGSize,
        margin: CGFloat = 200
    ) -> Bool {
        let screenX = position.x * Double(scale) + Double(offset.width)
        let screenY = position.y * Double(scale) + Double(offset.height)
        let width = cardWidth * Double(scale)
        let height = cardHeight * Double(scale)
        return screenX + width >= -Double(margin)
            && screenX <= Double(viewport.width) + Double(margin)
            && screenY + height >= -Double(margin)
            && screenY <= Double(viewport.height) + Double(margin)
    }

    public static func nextFocusID(
        from currentID: String,
        direction: FocusDirection,
        tables: [CanvasTable],
        heights: [String: Double]
    ) -> String? {
        guard let current = tables.first(where: { $0.id == currentID }) else { return nil }
        let currentCenter = center(of: current, height: heights[currentID] ?? 100)

        var bestID: String?
        var bestScore = Double.greatestFiniteMagnitude
        for candidate in tables where candidate.id != currentID {
            let candidateCenter = center(of: candidate, height: heights[candidate.id] ?? 100)
            let dx = candidateCenter.x - currentCenter.x
            let dy = candidateCenter.y - currentCenter.y
            let (primary, perpendicular): (Double, Double)
            switch direction {
            case .up:
                (primary, perpendicular) = (-dy, abs(dx))
            case .down:
                (primary, perpendicular) = (dy, abs(dx))
            case .left:
                (primary, perpendicular) = (-dx, abs(dy))
            case .right:
                (primary, perpendicular) = (dx, abs(dy))
            }
            guard primary > 1 else { continue }
            let score = primary + perpendicular * 2
            if score < bestScore {
                bestScore = score
                bestID = candidate.id
            }
        }
        return bestID
    }

    public enum FocusDirection {
        case up, down, left, right
    }

    private static func center(of table: CanvasTable, height: Double) -> CGPoint {
        CGPoint(
            x: table.position.x + CanvasCardMetrics.cardWidth / 2,
            y: table.position.y + height / 2
        )
    }
}
