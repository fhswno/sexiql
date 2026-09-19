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

    public func qualifiedName(kind: DatabaseKind) -> String {
        let quote = { SchemaBrowser.quoteIdentifier($0, kind: kind) }
        if let schema, !schema.isEmpty {
            return quote(schema) + "." + quote(name)
        }
        return quote(name)
    }
}

public enum CellUpdateSQL: Sendable {
    public static func statement(table: EditableTable, column: Int, kind: DatabaseKind) -> String {
        let quote = { SchemaBrowser.quoteIdentifier($0, kind: kind) }
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
        return "UPDATE \(table.qualifiedName(kind: kind)) SET \(columnName) = \(set) WHERE " + conditions.joined(separator: " AND ")
    }
}

public enum CellDeleteSQL: Sendable {
    public static func statement(table: EditableTable, kind: DatabaseKind) -> String {
        let quote = { SchemaBrowser.quoteIdentifier($0, kind: kind) }
        let placeholders: [String]
        if kind == .postgres {
            placeholders = table.primaryKey.indices.map { "$\($0 + 1)" }
        } else {
            placeholders = Array(repeating: "?", count: table.primaryKey.count)
        }
        var conditions: [String] = []
        for (index, pk) in table.primaryKey.enumerated() where index < placeholders.count {
            conditions.append("\(quote(pk)) = \(placeholders[index])")
        }
        return "DELETE FROM \(table.qualifiedName(kind: kind)) WHERE " + conditions.joined(separator: " AND ")
    }
}

public enum CellInsertSQL: Sendable {
    public static func defaultValues(table: EditableTable, kind: DatabaseKind) -> String {
        let name = table.qualifiedName(kind: kind)
        switch kind {
        case .postgres, .sqlite:
            return "INSERT INTO \(name) DEFAULT VALUES RETURNING *"
        case .mysql:
            return "INSERT INTO \(name) () VALUES ()"
        case .redis:
            return ""
        }
    }

    public static func lastInsertID(kind: DatabaseKind) -> String? {
        switch kind {
        case .mysql: "SELECT LAST_INSERT_ID()"
        case .sqlite: "SELECT last_insert_rowid()"
        case .postgres, .redis: nil
        }
    }

    public static func explicit(table: EditableTable, columnNames: [String], kind: DatabaseKind) -> String {
        let quote = { SchemaBrowser.quoteIdentifier($0, kind: kind) }
        let cols = columnNames.map(quote).joined(separator: ", ")
        let placeholders: String
        if kind == .postgres {
            placeholders = columnNames.indices.map { "$\($0 + 1)" }.joined(separator: ", ")
        } else {
            placeholders = Array(repeating: "?", count: columnNames.count).joined(separator: ", ")
        }
        let sql = "INSERT INTO \(table.qualifiedName(kind: kind)) (\(cols)) VALUES (\(placeholders))"
        if kind == .postgres || kind == .sqlite {
            return sql + " RETURNING *"
        }
        return sql
    }

    public static func selectByPrimaryKey(table: EditableTable, selectColumns: [String], kind: DatabaseKind) -> String {
        let quote = { SchemaBrowser.quoteIdentifier($0, kind: kind) }
        let cols = selectColumns.map(quote).joined(separator: ", ")
        let placeholders: [String]
        if kind == .postgres {
            placeholders = table.primaryKey.indices.map { "$\($0 + 1)" }
        } else {
            placeholders = Array(repeating: "?", count: table.primaryKey.count)
        }
        var conditions: [String] = []
        for (index, pk) in table.primaryKey.enumerated() where index < placeholders.count {
            conditions.append("\(quote(pk)) = \(placeholders[index])")
        }
        return "SELECT \(cols) FROM \(table.qualifiedName(kind: kind)) WHERE " + conditions.joined(separator: " AND ")
    }
}

public enum DraftRowRequirements: Sendable {
    public static func missing(
        columns: [SQLColumn],
        values: [SQLValue],
        primaryKey: [String]
    ) -> [String] {
        let pk = Set(primaryKey.map { $0.lowercased() })
        var names: [String] = []
        for (index, column) in columns.enumerated() {
            if column.isNullable { continue }
            if pk.contains(column.name.lowercased()) { continue }
            let value = values.indices.contains(index) ? values[index] : .null
            if isEmpty(value) {
                names.append(column.name)
            }
        }
        return names
    }

    private static func isEmpty(_ value: SQLValue) -> Bool {
        switch value {
        case .null: true
        case .string(let text): text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: false
        }
    }
}

public enum MutationRowIndex: Sendable {
    public static func afterDelete(_ row: Int, deleted: Int) -> Int? {
        if row == deleted { return nil }
        if row > deleted { return row - 1 }
        return row
    }

    public static func afterInsert(_ row: Int, inserted: Int) -> Int {
        row >= inserted ? row + 1 : row
    }
}

public struct EditableTableResolver: Sendable {
    public init() {}

    public func resolve(for connection: any DatabaseConnection, columns: [SQLColumn]) async throws -> EditableTable? {
        let candidate = try await candidateTable(for: connection, columns: columns)
        guard let candidate else { return nil }
        let schema: String?
        let resolvedKeys: [String]
        switch connection.profile.kind {
        case .postgres:
            schema = candidate.schema
            resolvedKeys = try await primaryKey(
                for: connection,
                kind: .postgres,
                table: candidate.name,
                schema: candidate.schema
            )
        case .mysql, .sqlite, .redis:
            schema = Self.singleSchema(from: columns)
            resolvedKeys = try await primaryKey(
                for: connection,
                kind: connection.profile.kind,
                table: candidate.name,
                schema: schema
            )
        }
        guard !resolvedKeys.isEmpty else { return nil }
        return EditableTable(name: candidate.name, columns: columns.map(\.name), primaryKey: resolvedKeys, schema: schema)
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

    private func candidateTable(for connection: any DatabaseConnection, columns: [SQLColumn]) async throws -> (name: String, schema: String?)? {
        switch connection.profile.kind {
        case .sqlite, .mysql:
            return Self.singleTableName(from: columns).map { ($0, Self.singleSchema(from: columns)) }
        case .postgres:
            let oids = Set(columns.compactMap(\.tableOID))
            guard oids.count == 1, let oid = oids.first, oid != 0 else { return nil }
            return try await resolveTableIdentity(for: connection, oid: oid)
        case .redis:
            return nil
        }
    }

    private func resolveTableIdentity(for connection: any DatabaseConnection, oid: UInt32) async throws -> (name: String, schema: String?)? {
        let result = try await connection.execute(
            """
            SELECT c.relname, n.nspname
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE c.oid = $1
            """,
            parameters: [.int(Int64(oid))]
        )
        guard let row = result.rows.first else { return nil }
        guard case .string(let name) = row.values.first else { return nil }
        let schema: String?
        if row.values.count > 1, case .string(let namespace) = row.values[1] {
            schema = namespace
        } else {
            schema = nil
        }
        return (name, schema)
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
            let sql: String
            let parameters: [SQLValue]
            if let schema, !schema.isEmpty {
                sql = """
                SELECT a.attname
                FROM pg_catalog.pg_index i
                JOIN pg_catalog.pg_attribute a
                  ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE i.indrelid = (
                        SELECT c.oid
                        FROM pg_catalog.pg_class c
                        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                        WHERE c.relname = $1 AND n.nspname = $2
                      )
                  AND i.indisprimary
                ORDER BY array_position(i.indkey, a.attnum)
                """
                parameters = [.string(table), .string(schema)]
            } else {
                sql = """
                SELECT a.attname
                FROM pg_catalog.pg_index i
                JOIN pg_catalog.pg_attribute a
                  ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE i.indrelid = (
                        SELECT c.oid
                        FROM pg_catalog.pg_class c
                        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                        WHERE c.relname = $1 AND n.nspname = ANY(current_schemas(false))
                        ORDER BY array_position(current_schemas(false), n.nspname)
                        LIMIT 1
                      )
                  AND i.indisprimary
                ORDER BY array_position(i.indkey, a.attnum)
                """
                parameters = [.string(table)]
            }
            let result = try await connection.execute(sql, parameters: parameters)
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
        case .redis:
            return []
        }
    }

    private func escaped(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
