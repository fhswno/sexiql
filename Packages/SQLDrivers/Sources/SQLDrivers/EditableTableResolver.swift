import Foundation
import SQLCore

public struct EditableTable: Sendable, Equatable {
    public var name: String
    public var columns: [String]
    public var primaryKey: [String]
    public var schema: String?

    public init(name: String, columns: [String], primaryKey: [String], schema: String? = nil) {
        self.name = name
        self.columns = columns
        self.primaryKey = primaryKey
        self.schema = schema
    }

    public var isEditable: Bool { !primaryKey.isEmpty }
}

public enum CellUpdateSQL: Sendable {
    public static func statement(table: EditableTable, column: Int, kind: DatabaseKind) -> String {
        let quote = { SchemaBrowser.quoteIdentifier($0, kind: kind) }
        let tableName: String
        if let schema = table.schema, !schema.isEmpty {
            tableName = quote(schema) + "." + quote(table.name)
        } else {
            tableName = quote(table.name)
        }
        let columnName = quote(table.columns[column])
        let pkCount = table.primaryKey.count
        let set: String
        let placeholders: [String]
        if kind == .postgres {
            set = "$1"
            placeholders = (0..<pkCount).map { "$\($0 + 2)" }
        } else {
            set = "?"
            placeholders = Array(repeating: "?", count: pkCount)
        }
        var conditions: [String] = []
        for (index, pk) in table.primaryKey.enumerated() where index < placeholders.count {
            conditions.append("\(quote(pk)) = \(placeholders[index])")
        }
        return "UPDATE \(tableName) SET \(columnName) = \(set) WHERE " + conditions.joined(separator: " AND ")
    }
}

public struct EditableTableResolver: Sendable {
    public init() {}

    public func resolve(for connection: any DatabaseConnection, columns: [SQLColumn]) async throws -> EditableTable? {
        let candidate = try await candidateTable(for: connection, columns: columns)
        guard let candidate else { return nil }
        let schema = Self.singleSchema(from: columns)
        let primaryKey = try await primaryKey(
            for: connection,
            kind: connection.profile.kind,
            table: candidate,
            schema: schema
        )
        guard !primaryKey.isEmpty else { return nil }
        return EditableTable(name: candidate, columns: columns.map(\.name), primaryKey: primaryKey, schema: schema)
    }

    static func singleTableName(from columns: [SQLColumn]) -> String? {
        let tables = Set(columns.compactMap(\.tableName).filter { !$0.isEmpty && $0 != "(null)" })
        guard tables.count == 1, let table = tables.first else { return nil }
        return table
    }

    static func singleSchema(from columns: [SQLColumn]) -> String? {
        let schemas = Set(columns.compactMap(\.tableSchema).filter { !$0.isEmpty })
        guard schemas.count == 1, let schema = schemas.first else { return nil }
        return schema
    }

    private func candidateTable(for connection: any DatabaseConnection, columns: [SQLColumn]) async throws -> String? {
        switch connection.profile.kind {
        case .sqlite, .mysql:
            return Self.singleTableName(from: columns)
        case .postgres:
            let oids = Set(columns.compactMap(\.tableOID))
            guard oids.count == 1, let oid = oids.first, oid != 0 else { return nil }
            return try await resolveTableName(for: connection, oid: oid)
        }
    }

    private func resolveTableName(for connection: any DatabaseConnection, oid: UInt32) async throws -> String? {
        let result = try await connection.execute(
            "SELECT c.relname FROM pg_catalog.pg_class c WHERE c.oid = $1",
            parameters: [.int(Int64(oid))]
        )
        if case .string(let name) = result.rows.first?.values.first {
            return name
        }
        return nil
    }

    private func primaryKey(
        for connection: any DatabaseConnection,
        kind: DatabaseKind,
        table: String,
        schema: String?
    ) async throws -> [String] {
        switch kind {
        case .sqlite:
            let result = try await connection.execute("PRAGMA table_info(\"\(escaped(table))\")")
            let keyColumns = result.rows.compactMap { row -> String? in
                guard row.values.count >= 6,
                      case .int(let pkFlag) = row.values[5],
                      pkFlag > 0,
                      case .string(let name) = row.values[1] else {
                    return nil
                }
                return name
            }
            return keyColumns
        case .postgres:
            let result = try await connection.execute(
                """
                SELECT a.attname
                FROM pg_catalog.pg_index i
                JOIN pg_catalog.pg_attribute a
                  ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE i.indrelid = (SELECT c.oid FROM pg_catalog.pg_class c WHERE c.relname = $1)
                  AND i.indisprimary
                ORDER BY array_position(i.indkey, a.attnum)
                """,
                parameters: [.string(table)]
            )
            return result.rows.compactMap { row in
                if case .string(let name) = row.values.first { name } else { nil }
            }
        case .mysql:
            let result = try await connection.execute(
                """
                SELECT COLUMN_NAME
                FROM information_schema.KEY_COLUMN_USAGE
                WHERE TABLE_SCHEMA = COALESCE(?, DATABASE())
                  AND TABLE_NAME = ?
                  AND CONSTRAINT_NAME = 'PRIMARY'
                ORDER BY ORDINAL_POSITION
                """,
                parameters: [schema.map { .string($0) } ?? .null, .string(table)]
            )
            return result.rows.compactMap { row in
                if case .string(let name) = row.values.first { name } else { nil }
            }
        }
    }

    private func escaped(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
