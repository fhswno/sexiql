public struct CanvasEdge: Sendable, Hashable, Identifiable {
    public var id: String
    public var fromTableID: String
    public var fromColumn: String
    public var toTableID: String
    public var toColumn: String
    public var isVirtual: Bool

    public init(
        fromTableID: String,
        fromColumn: String,
        toTableID: String,
        toColumn: String,
        isVirtual: Bool = false
    ) {
        self.id = "\(fromTableID).\(fromColumn)->\(toTableID).\(toColumn)"
        self.fromTableID = fromTableID
        self.fromColumn = fromColumn
        self.toTableID = toTableID
        self.toColumn = toColumn
        self.isVirtual = isVirtual
    }
}
