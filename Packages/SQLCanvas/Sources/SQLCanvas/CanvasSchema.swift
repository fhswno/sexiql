public struct CanvasPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CanvasColumn: Sendable, Hashable, Identifiable {
    public var name: String
    public var dataType: String
    public var isPrimaryKey: Bool
    public var isForeignKey: Bool
    public var isNullable: Bool

    public var id: String { name }

    public init(
        name: String,
        dataType: String,
        isPrimaryKey: Bool = false,
        isForeignKey: Bool = false,
        isNullable: Bool = true
    ) {
        self.name = name
        self.dataType = dataType
        self.isPrimaryKey = isPrimaryKey
        self.isForeignKey = isForeignKey
        self.isNullable = isNullable
    }
}

public struct CanvasTable: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var schema: String?
    public var columns: [CanvasColumn]
    public var position: CanvasPoint

    public init(id: String, name: String, schema: String? = nil, columns: [CanvasColumn], position: CanvasPoint) {
        self.id = id
        self.name = name
        self.schema = schema
        self.columns = columns
        self.position = position
    }
}

public struct CanvasSchema: Sendable {
    public var tables: [CanvasTable]

    public init(tables: [CanvasTable]) {
        self.tables = tables
    }

    public func table(withID id: String) -> CanvasTable? {
        tables.first { $0.id == id }
    }
}
