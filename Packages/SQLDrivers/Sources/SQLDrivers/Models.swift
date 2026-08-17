import Foundation
import SQLCore

public struct SQLColumn: Sendable, Equatable {
    public var name: String
    public var dataType: String
    public var isNullable: Bool
    public var ordinal: Int
    public var tableName: String?
    public var tableOID: UInt32?

    public init(
        name: String,
        dataType: String,
        isNullable: Bool = true,
        ordinal: Int,
        tableName: String? = nil,
        tableOID: UInt32? = nil
    ) {
        self.name = name
        self.dataType = dataType
        self.isNullable = isNullable
        self.ordinal = ordinal
        self.tableName = tableName
        self.tableOID = tableOID
    }
}

public enum SQLValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)

    public var text: String? {
        switch self {
        case .null: nil
        case .string(let value): value
        default: displayString
        }
    }

    public var displayString: String {
        switch self {
        case .null: "NULL"
        case .bool(let value): value ? "true" : "false"
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .string(let value): value
        case .data(let value): "<\(value.count) bytes>"
        case .date(let value): ISO8601DateFormatter().string(from: value)
        }
    }
}

public struct SQLRow: Sendable, Equatable {
    public var values: [SQLValue]

    public init(values: [SQLValue]) {
        self.values = values
    }
}

public typealias RowStream = AsyncThrowingStream<SQLRow, Error>

public struct StreamedQuery: Sendable {
    public var columns: [SQLColumn]
    public var rows: RowStream

    public init(columns: [SQLColumn], rows: RowStream) {
        self.columns = columns
        self.rows = rows
    }
}

public struct QueryResult: Sendable, Equatable {
    public var columns: [SQLColumn]?
    public var rows: [SQLRow]
    public var affectedRowCount: Int?

    public var isResultSet: Bool { columns != nil }

    public init(columns: [SQLColumn]? = nil, rows: [SQLRow] = [], affectedRowCount: Int? = nil) {
        self.columns = columns
        self.rows = rows
        self.affectedRowCount = affectedRowCount
    }
}

public enum SQLDriverError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedDatabase(DatabaseKind)
    case notImplemented(feature: String)
    case connectionFailed(message: String)
    case sqlite(message: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupportedDatabase(let kind):
            "Unsupported database: \(kind.displayName)"
        case .notImplemented(let feature):
            "Not implemented: \(feature)"
        case .connectionFailed(let message):
            message
        case .sqlite(let message):
            message
        case .cancelled:
            "Cancelled"
        }
    }
}
