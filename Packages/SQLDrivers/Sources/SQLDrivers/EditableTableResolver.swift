import Foundation
import SQLCore

public struct EditableTable: Sendable, Equatable {
    public var name: String
    public var columns: [String]
    public var primaryKey: [String]

    public init(name: String, columns: [String], primaryKey: [String]) {
        self.name = name
        self.columns = columns
        self.primaryKey = primaryKey
    }

    public var isEditable: Bool { !primaryKey.isEmpty }
}

public struct EditableTableResolver: Sendable {
    public init() {}

    public func resolve(for connection: any DatabaseConnection, columns: [SQLColumn]) async throws -> EditableTable? {
        let candidate = try await candidateTable(for: connection, columns: columns)
        guard let candidate else { return nil }
        let primaryKey = try await primaryKey(for: connection, kind: connection.profile.kind, table: candidate)
        guard !primaryKey.isEmpty else { return nil }
        return EditableTable(name: candidate, columns: columns.map(\.name), primaryKey: primaryKey)
    }

    private func candidateTable(for connection: any DatabaseConnection, columns: [SQLColumn]) async throws -> String? {
        switch connection.profile.kind {
        case .sqlite:
            let tables = Set(columns.compactMap(\.tableName).filter { !$0.isEmpty && $0 != "(null)" })
            guard tables.count == 1, let table = tables.first else { return nil }
            return table
        case .postgres:
            let oids = Set(columns.compactMap(\.tableOID))
            guard oids.count == 1, let oid = oids.first, oid != 0 else { return nil }
            return try await resolveTableName(for: connection, oid: oid)
        case .mysql:
            return nil
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

    private func primaryKey(for connection: any DatabaseConnection, kind: DatabaseKind, table: String) async throws -> [String] {
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
            return []
        }
    }

    private func escaped(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
