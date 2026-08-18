import Foundation
import SQLCore

public struct SchemaIndex: Sendable, Hashable, Identifiable {
    public var name: String
    public var columns: [String]
    public var isUnique: Bool
    public var isPrimary: Bool

    public var id: String { "\(name)|\(columns.joined(separator: ","))" }

    public init(name: String, columns: [String], isUnique: Bool, isPrimary: Bool) {
        self.name = name
        self.columns = columns
        self.isUnique = isUnique
        self.isPrimary = isPrimary
    }

    public var detail: String {
        let cols = columns.isEmpty ? "" : " (\(columns.joined(separator: ", ")))"
        if isPrimary { return "PRIMARY\(cols)" }
        if isUnique { return "UNIQUE\(cols)" }
        return "INDEX\(cols)"
    }
}

public struct SchemaForeignKey: Sendable, Hashable, Identifiable {
    public var name: String
    public var columns: [String]
    public var refSchema: String?
    public var refTable: String
    public var refColumns: [String]

    public var id: String {
        "\(name)|\(columns.joined(separator: ","))|\(refTable)|\(refColumns.joined(separator: ","))"
    }

    public init(
        name: String,
        columns: [String],
        refTable: String,
        refColumns: [String],
        refSchema: String? = nil
    ) {
        self.name = name
        self.columns = columns
        self.refSchema = refSchema
        self.refTable = refTable
        self.refColumns = refColumns
    }

    public var detail: String {
        let from = columns.joined(separator: ", ")
        let to = refColumns.joined(separator: ", ")
        let table = refSchema.map { "\($0).\(refTable)" } ?? refTable
        if from.isEmpty { return "→ \(table)" }
        return "\(from) → \(table).\(to)"
    }
}

extension SchemaBrowser {
    public static func ensuringPrimaryIndex(
        _ indexes: [SchemaIndex],
        columns: [SchemaColumn]
    ) -> [SchemaIndex] {
        if indexes.contains(where: \.isPrimary) { return indexes }
        let pk = columns.filter(\.isPrimaryKey).map(\.name)
        guard !pk.isEmpty else { return indexes }
        let synthesized = SchemaIndex(name: "PRIMARY", columns: pk, isUnique: true, isPrimary: true)
        return [synthesized] + indexes
    }

    public static func listIndexes(
        on connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaIndex] {
        switch connection.profile.kind {
        case .sqlite:
            return try await sqliteIndexes(connection, table: object.name)
        case .postgres:
            return try await postgresIndexes(connection, object: object)
        case .mysql:
            return try await mysqlIndexes(connection, object: object)
        case .redis:
            return []
        }
    }

    public static func listForeignKeys(
        on connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaForeignKey] {
        switch connection.profile.kind {
        case .sqlite:
            return try await sqliteForeignKeys(connection, table: object.name)
        case .postgres:
            return try await postgresForeignKeys(connection, object: object)
        case .mysql:
            return try await mysqlForeignKeys(connection, object: object)
        case .redis:
            return []
        }
    }

    public static func indexes(fromPostgresRows rows: [SQLRow]) -> [SchemaIndex] {
        groupedIndexes(rows, nameAt: 0, uniqueAt: 1, primaryAt: 2, columnAt: 3)
    }

    public static func indexes(fromMySQLRows rows: [SQLRow]) -> [SchemaIndex] {
        var order: [String] = []
        var columns: [String: [String]] = [:]
        var unique: [String: Bool] = [:]
        var primary: [String: Bool] = [:]
        for row in rows {
            guard let name = row.values[safe: 0]?.text, !name.isEmpty else { continue }
            if columns[name] == nil { order.append(name) }
            let nonUnique = intValue(row.values[safe: 1])
            unique[name] = (unique[name] ?? true) && nonUnique == 0
            primary[name] = (primary[name] ?? false) || name.uppercased() == "PRIMARY"
            if let col = row.values[safe: 2]?.text, !col.isEmpty {
                columns[name, default: []].append(col)
            }
        }
        return order.map {
            SchemaIndex(name: $0, columns: columns[$0] ?? [], isUnique: unique[$0] ?? false, isPrimary: primary[$0] ?? false)
        }
    }

    public static func foreignKeys(fromPostgresRows rows: [SQLRow]) -> [SchemaForeignKey] {
        groupedForeignKeys(rows, nameAt: 0, columnAt: 1, refSchemaAt: 2, refTableAt: 3, refColumnAt: 4)
    }

    public static func foreignKeys(fromMySQLRows rows: [SQLRow]) -> [SchemaForeignKey] {
        groupedForeignKeys(rows, nameAt: 0, columnAt: 1, refSchemaAt: 2, refTableAt: 3, refColumnAt: 4)
    }

    public static func foreignKeys(fromSQLiteRows rows: [SQLRow]) -> [SchemaForeignKey] {
        var order: [String] = []
        var grouped: [String: SchemaForeignKey] = [:]
        for row in rows {
            let id = row.values[safe: 0].map { intValue($0) } ?? 0
            let key = "fk_\(id)"
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = SchemaForeignKey(
                    name: key,
                    columns: [],
                    refTable: row.values[safe: 2]?.text ?? "",
                    refColumns: []
                )
            }
            if let from = row.values[safe: 3]?.text, !from.isEmpty {
                grouped[key]?.columns.append(from)
            }
            if let to = row.values[safe: 4]?.text, !to.isEmpty {
                grouped[key]?.refColumns.append(to)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    // MARK: - Engine loaders

    private static func sqliteIndexes(
        _ connection: any DatabaseConnection,
        table: String
    ) async throws -> [SchemaIndex] {
        let quoted = quoteIdentifier(table, kind: .sqlite)
        let list = try await connection.execute("PRAGMA index_list(\(quoted))")
        var indexes: [SchemaIndex] = []
        for row in list.rows {
            guard let name = row.values[safe: 1]?.text, !name.isEmpty else { continue }
            let unique = intValue(row.values[safe: 2]) != 0
            let origin = row.values[safe: 3]?.text?.lowercased() ?? ""
            let info = try await connection.execute("PRAGMA index_info(\(quoteIdentifier(name, kind: .sqlite)))")
            let columns = info.rows.compactMap { $0.values[safe: 2]?.text }
            indexes.append(
                SchemaIndex(name: name, columns: columns, isUnique: unique, isPrimary: origin == "pk")
            )
        }
        return indexes
    }

    private static func sqliteForeignKeys(
        _ connection: any DatabaseConnection,
        table: String
    ) async throws -> [SchemaForeignKey] {
        let quoted = quoteIdentifier(table, kind: .sqlite)
        let result = try await connection.execute("PRAGMA foreign_key_list(\(quoted))")
        return foreignKeys(fromSQLiteRows: result.rows)
    }

    private static func postgresIndexes(
        _ connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaIndex] {
        let schema = object.schema ?? "public"
        let sql = """
        SELECT i.relname,
               ix.indisunique,
               ix.indisprimary,
               a.attname
        FROM pg_catalog.pg_class t
        JOIN pg_catalog.pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_catalog.pg_index ix ON ix.indrelid = t.oid
        JOIN pg_catalog.pg_class i ON i.oid = ix.indexrelid
        JOIN pg_catalog.pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY (ix.indkey)
        WHERE n.nspname = $1 AND t.relname = $2
        ORDER BY i.relname, array_position(ix.indkey, a.attnum)
        """
        let result = try await connection.execute(sql, parameters: [.string(schema), .string(object.name)])
        return indexes(fromPostgresRows: result.rows)
    }

    private static func postgresForeignKeys(
        _ connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaForeignKey] {
        let schema = object.schema ?? "public"
        let sql = """
        SELECT tc.constraint_name,
               kcu.column_name,
               ccu.table_schema,
               ccu.table_name,
               ccu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
         AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = $1 AND tc.table_name = $2
        ORDER BY tc.constraint_name, kcu.ordinal_position
        """
        let result = try await connection.execute(sql, parameters: [.string(schema), .string(object.name)])
        return foreignKeys(fromPostgresRows: result.rows)
    }

    private static func mysqlIndexes(
        _ connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaIndex] {
        let schema = object.schema ?? connection.profile.database
        let sql = """
        SELECT INDEX_NAME, NON_UNIQUE, COLUMN_NAME
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
        ORDER BY INDEX_NAME, SEQ_IN_INDEX
        """
        let result = try await connection.execute(
            sql,
            parameters: [.string(schema), .string(object.name)]
        )
        return indexes(fromMySQLRows: result.rows)
    }

    private static func mysqlForeignKeys(
        _ connection: any DatabaseConnection,
        object: SchemaObject
    ) async throws -> [SchemaForeignKey] {
        let schema = object.schema ?? connection.profile.database
        let sql = """
        SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_SCHEMA,
               REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
          AND REFERENCED_TABLE_NAME IS NOT NULL
        ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION
        """
        let result = try await connection.execute(
            sql,
            parameters: [.string(schema), .string(object.name)]
        )
        return foreignKeys(fromMySQLRows: result.rows)
    }

    private static func groupedIndexes(
        _ rows: [SQLRow],
        nameAt: Int,
        uniqueAt: Int,
        primaryAt: Int,
        columnAt: Int
    ) -> [SchemaIndex] {
        var order: [String] = []
        var columns: [String: [String]] = [:]
        var unique: [String: Bool] = [:]
        var primary: [String: Bool] = [:]
        for row in rows {
            guard let name = row.values[safe: nameAt]?.text, !name.isEmpty else { continue }
            if columns[name] == nil { order.append(name) }
            unique[name] = (unique[name] ?? false) || boolValue(row.values[safe: uniqueAt])
            primary[name] = (primary[name] ?? false) || boolValue(row.values[safe: primaryAt])
            if let col = row.values[safe: columnAt]?.text, !col.isEmpty {
                columns[name, default: []].append(col)
            }
        }
        return order.map {
            SchemaIndex(name: $0, columns: columns[$0] ?? [], isUnique: unique[$0] ?? false, isPrimary: primary[$0] ?? false)
        }
    }

    private static func groupedForeignKeys(
        _ rows: [SQLRow],
        nameAt: Int,
        columnAt: Int,
        refSchemaAt: Int,
        refTableAt: Int,
        refColumnAt: Int
    ) -> [SchemaForeignKey] {
        var order: [String] = []
        var grouped: [String: SchemaForeignKey] = [:]
        for row in rows {
            guard let name = row.values[safe: nameAt]?.text, !name.isEmpty else { continue }
            if grouped[name] == nil {
                order.append(name)
                grouped[name] = SchemaForeignKey(
                    name: name,
                    columns: [],
                    refTable: row.values[safe: refTableAt]?.text ?? "",
                    refColumns: [],
                    refSchema: emptyToNil(row.values[safe: refSchemaAt]?.text)
                )
            }
            if let col = row.values[safe: columnAt]?.text, !col.isEmpty {
                grouped[name]?.columns.append(col)
            }
            if let ref = row.values[safe: refColumnAt]?.text, !ref.isEmpty {
                grouped[name]?.refColumns.append(ref)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    private static func boolValue(_ value: SQLValue?) -> Bool {
        switch value {
        case .bool(let flag): flag
        case .int(let number): number != 0
        case .string(let text):
            ["t", "true", "yes", "1"].contains(text.lowercased())
        default: false
        }
    }

    private static func intValue(_ value: SQLValue?) -> Int64 {
        switch value {
        case .int(let number): number
        case .string(let text): Int64(text) ?? 0
        default: 0
        }
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
