import Foundation
import SQLCore

public enum SchemaObjectKind: String, Sendable, Hashable, CaseIterable {
    case table
    case view
}

public struct SchemaObject: Sendable, Hashable, Identifiable {
    public var id: String
    public var schema: String?
    public var name: String
    public var kind: SchemaObjectKind

    public init(schema: String?, name: String, kind: SchemaObjectKind) {
        self.schema = schema
        self.name = name
        self.kind = kind
        if let schema, !schema.isEmpty {
            self.id = "\(schema).\(name)"
        } else {
            self.id = name
        }
    }

    public var displayName: String {
        if let schema, !schema.isEmpty { return "\(schema).\(name)" }
        return name
    }
}

public struct SchemaColumn: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var dataType: String
    public var isPrimaryKey: Bool
    public var isNullable: Bool

    public init(name: String, dataType: String, isPrimaryKey: Bool, isNullable: Bool) {
        self.name = name
        self.dataType = dataType
        self.isPrimaryKey = isPrimaryKey
        self.isNullable = isNullable
    }
}

public enum SchemaBrowser: Sendable {
    public static func listObjects(on connection: any DatabaseConnection) async throws -> [SchemaObject] {
        let kind = connection.profile.kind
        let sql: String
        switch kind {
        case .sqlite:
            sql = """
            SELECT name, type FROM sqlite_master
            WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """
        case .postgres:
            sql = """
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
            ORDER BY table_schema, table_name
            """
        case .mysql:
            sql = """
            SELECT table_schema, table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
            ORDER BY table_name
            """
        }
        let result = try await connection.execute(sql)
        return result.rows.compactMap { row in parseObjectRow(row, kind: kind) }
    }

    public static func listColumns(
        on connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaColumn] {
        switch connection.profile.kind {
        case .sqlite:
            return try await sqliteColumns(connection, table: object.name)
        case .postgres:
            return try await postgresColumns(connection, object: object)
        case .mysql:
            return try await mysqlColumns(connection, object: object)
        }
    }

    public static func quoteIdentifier(_ name: String, kind: DatabaseKind) -> String {
        switch kind {
        case .mysql:
            let escaped = name.replacingOccurrences(of: "`", with: "``")
            return "`\(escaped)`"
        case .postgres, .sqlite:
            let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
    }

    public static func qualify(_ object: SchemaObject, kind: DatabaseKind) -> String {
        let table = quoteIdentifier(object.name, kind: kind)
        guard let schema = object.schema, !schema.isEmpty else { return table }
        return "\(quoteIdentifier(schema, kind: kind)).\(table)"
    }

    public static func selectAllSQL(_ object: SchemaObject, kind: DatabaseKind, limit: Int = 1000) -> String {
        "SELECT * FROM \(qualify(object, kind: kind)) LIMIT \(limit);"
    }

    // MARK: - Private

    private static func parseObjectRow(_ row: SQLRow, kind: DatabaseKind) -> SchemaObject? {
        switch kind {
        case .sqlite:
            guard row.values.count >= 2,
                  case .string(let name) = row.values[0] else { return nil }
            let typeStr: String
            if case .string(let t) = row.values[1] { typeStr = t.lowercased() } else { typeStr = "table" }
            let objKind: SchemaObjectKind = typeStr.contains("view") ? .view : .table
            return SchemaObject(schema: nil, name: name, kind: objKind)
        case .postgres, .mysql:
            guard row.values.count >= 3,
                  case .string(let schema) = row.values[0],
                  case .string(let name) = row.values[1] else { return nil }
            let typeStr: String
            if case .string(let t) = row.values[2] { typeStr = t.uppercased() } else { typeStr = "BASE TABLE" }
            let objKind: SchemaObjectKind = typeStr.contains("VIEW") ? .view : .table
            return SchemaObject(schema: schema, name: name, kind: objKind)
        }
    }

    private static func sqliteColumns(
        _ connection: any DatabaseConnection,
        table: String
    ) async throws -> [SchemaColumn] {
        let quoted = quoteIdentifier(table, kind: .sqlite)
        let result = try await connection.execute("PRAGMA table_info(\(quoted))")
        return result.rows.compactMap { row -> SchemaColumn? in
            guard row.values.count >= 6,
                  case .string(let name) = row.values[1] else { return nil }
            let typeName: String
            if case .string(let t) = row.values[2] { typeName = t } else { typeName = "" }
            let notNull: Bool
            if case .int(let n) = row.values[3] { notNull = n != 0 } else { notNull = false }
            let pk: Bool
            if case .int(let n) = row.values[5] { pk = n > 0 } else { pk = false }
            return SchemaColumn(name: name, dataType: typeName, isPrimaryKey: pk, isNullable: !notNull)
        }
    }

    private static func postgresColumns(
        _ connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaColumn] {
        let schema = object.schema ?? "public"
        let sql = """
        SELECT c.column_name, c.data_type, c.is_nullable,
               CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN true ELSE false END AS is_pk
        FROM information_schema.columns c
        LEFT JOIN information_schema.key_column_usage kcu
          ON c.table_schema = kcu.table_schema
         AND c.table_name = kcu.table_name
         AND c.column_name = kcu.column_name
        LEFT JOIN information_schema.table_constraints tc
          ON kcu.constraint_name = tc.constraint_name
         AND kcu.table_schema = tc.table_schema
         AND tc.constraint_type = 'PRIMARY KEY'
        WHERE c.table_schema = $1 AND c.table_name = $2
        ORDER BY c.ordinal_position
        """
        let result = try await connection.execute(sql, parameters: [.string(schema), .string(object.name)])
        return result.rows.compactMap { row -> SchemaColumn? in
            guard row.values.count >= 4,
                  case .string(let name) = row.values[0] else { return nil }
            let typeName: String
            if case .string(let t) = row.values[1] { typeName = t } else { typeName = "" }
            let nullable: Bool
            if case .string(let n) = row.values[2] { nullable = n.uppercased() == "YES" } else { nullable = true }
            let pk: Bool
            switch row.values[3] {
            case .bool(let b): pk = b
            case .string(let s): pk = s.lowercased() == "true" || s == "t"
            default: pk = false
            }
            return SchemaColumn(name: name, dataType: typeName, isPrimaryKey: pk, isNullable: nullable)
        }
    }

    private static func mysqlColumns(
        _ connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaColumn] {
        let schema = object.schema ?? connection.profile.database
        let sql = """
        SELECT c.COLUMN_NAME, c.COLUMN_TYPE, c.IS_NULLABLE, c.COLUMN_KEY
        FROM information_schema.COLUMNS c
        WHERE c.TABLE_SCHEMA = ? AND c.TABLE_NAME = ?
        ORDER BY c.ORDINAL_POSITION
        """
        let result = try await connection.execute(
            sql,
            parameters: [.string(schema), .string(object.name)]
        )
        return result.rows.compactMap { row -> SchemaColumn? in
            guard row.values.count >= 4,
                  case .string(let name) = row.values[0] else { return nil }
            let typeName: String
            if case .string(let t) = row.values[1] { typeName = t } else { typeName = "" }
            let nullable: Bool
            if case .string(let n) = row.values[2] { nullable = n.uppercased() == "YES" } else { nullable = true }
            let pk: Bool
            if case .string(let k) = row.values[3] { pk = k.uppercased() == "PRI" } else { pk = false }
            return SchemaColumn(name: name, dataType: typeName, isPrimaryKey: pk, isNullable: nullable)
        }
    }
}
