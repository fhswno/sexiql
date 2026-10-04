public enum CanvasCardMetrics {
    public static let cardWidth: Double = 260
    public static let headerHeight: Double = 34
    public static let rowHeight: Double = 22
    public static let rowInset: Double = 6

    public static func tableHeight(columnCount: Int, compact: Bool = false) -> Double {
        compact
            ? headerHeight
            : headerHeight + Double(max(columnCount, 1)) * rowHeight + rowInset
    }
}
