import Foundation
import SQLCore
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public actor SQLiteConnection: DatabaseConnection {
    public let profile: ConnectionProfile

    private final class SQLiteHandle: @unchecked Sendable {
        var db: OpaquePointer?
    }

    private var handle: SQLiteHandle?
    private let workQueue = DispatchQueue(label: "com.sexiql.driver.sqlite")

    public init(profile: ConnectionProfile) {
        self.profile = profile
    }

    public func isConnected() async -> Bool {
        handle != nil
    }

    public func connect(password: String?) async throws {
        guard handle == nil else { return }
        guard !profile.database.isEmpty else {
            throw SQLDriverError.sqlite(message: "No database file path set in the profile")
        }
        let newHandle = SQLiteHandle()
        let path = profile.database
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workQueue.async {
                var db: OpaquePointer?
                let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
                let status = sqlite3_open_v2(path, &db, flags, nil)
                if status == SQLITE_OK, let db {
                    newHandle.db = db
                    continuation.resume()
                } else {
                    let message: String
                    if let db {
                        message = String(cString: sqlite3_errmsg(db))
                    } else {
                        message = "sqlite3_open_v2 failed with status \(status)"
                    }
                    continuation.resume(throwing: SQLDriverError.sqlite(message: message))
                }
            }
        }
        handle = newHandle
    }

    public func disconnect() async throws {
        guard let handle else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            workQueue.async {
                sqlite3_close(handle.db)
                handle.db = nil
                continuation.resume()
            }
        }
        self.handle = nil
    }

    public func execute(_ sql: String) async throws -> QueryResult {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QueryResult, Error>) in
            workQueue.async {
                continuation.resume(with: SQLiteExecutor(db: handle.db).run(sql))
            }
        }
    }

    public func execute(_ sql: String, parameters: [SQLValue]) async throws -> QueryResult {
        let handle = try requireHandle()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QueryResult, Error>) in
            workQueue.async {
                continuation.resume(with: SQLiteExecutor(db: handle.db).run(sql, parameters: parameters))
            }
        }
    }

    public func stream(_ sql: String) async throws -> StreamedQuery {
        let handle = try requireHandle()
        let columns: [SQLColumn] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SQLColumn], Error>) in
            workQueue.async {
                var stmt: OpaquePointer?
                let status = sqlite3_prepare_v2(handle.db, sql, -1, &stmt, nil)
                guard status == SQLITE_OK, let stmt else {
                    let message = String(cString: sqlite3_errmsg(handle.db))
                    continuation.resume(throwing: SQLDriverError.sqlite(message: message))
                    return
                }
                let columns = Self.columns(from: stmt)
                sqlite3_finalize(stmt)
                continuation.resume(returning: columns)
            }
        }
        let stream: RowStream = RowStream { continuation in
            workQueue.async {
                SQLiteStreamer(db: handle.db, sql: sql).run(continuation: continuation)
            }
        }
        return StreamedQuery(columns: columns, rows: stream)
    }

    public func serverVersion() async throws -> String? {
        String(cString: sqlite3_libversion())
    }

    public func cancelInFlight() async {
        guard let handle else { return }
        // Safe from any thread while another thread is in sqlite3_step.
        if let db = handle.db {
            sqlite3_interrupt(db)
        }
    }

    private func requireHandle() throws -> SQLiteHandle {
        guard let handle else {
            throw SQLDriverError.connectionFailed(message: "Not connected")
        }
        return handle
    }

    // MARK: - Column and row decoding

    fileprivate static func columns(from stmt: OpaquePointer?) -> [SQLColumn] {
        let count = Int(sqlite3_column_count(stmt))
        return (0..<count).map { index in
            let i = Int32(index)
            let name = String(cString: sqlite3_column_name(stmt, i))
            let declared = sqlite3_column_decltype(stmt, i).map { String(cString: $0) } ?? ""
            let dataType = declared.isEmpty ? "sqlite" : declared
            let tableName = sqlite3_column_table_name(stmt, i).map { String(cString: $0) }
            return SQLColumn(
                name: name,
                dataType: dataType,
                isNullable: !declared.uppercased().contains("NOT NULL"),
                ordinal: index,
                tableName: tableName
            )
        }
    }

    fileprivate static func row(from stmt: OpaquePointer?, columnCount: Int) -> SQLRow {
        var values: [SQLValue] = []
        values.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            let i = Int32(index)
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER:
                values.append(.int(sqlite3_column_int64(stmt, i)))
            case SQLITE_FLOAT:
                values.append(.double(sqlite3_column_double(stmt, i)))
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(stmt, i) {
                    values.append(.string(String(cString: text)))
                } else {
                    values.append(.null)
                }
            case SQLITE_BLOB:
                if let blob = sqlite3_column_blob(stmt, i) {
                    let bytes = Int(sqlite3_column_bytes(stmt, i))
                    values.append(.data(Data(bytes: blob, count: bytes)))
                } else {
                    values.append(.null)
                }
            default:
                values.append(.null)
            }
        }
        return SQLRow(values: values)
    }

    fileprivate static func errorMessage(from db: OpaquePointer?) -> String {
        String(cString: sqlite3_errmsg(db))
    }
}

private struct SQLiteExecutor {
    let db: OpaquePointer?

    func run(_ sql: String, parameters: [SQLValue] = []) -> Result<QueryResult, Error> {
        var stmt: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareStatus == SQLITE_OK, let stmt else {
            return .failure(SQLDriverError.sqlite(message: SQLiteConnection.errorMessage(from: db)))
        }
        defer { sqlite3_finalize(stmt) }

        if let bindError = bind(parameters, to: stmt) {
            return .failure(bindError)
        }

        let columnCount = Int(sqlite3_column_count(stmt))
        var columns: [SQLColumn] = []
        if columnCount > 0 {
            columns = SQLiteConnection.columns(from: stmt)
        }
        var rows: [SQLRow] = []
        let isResultSet = columnCount > 0

        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                rows.append(SQLiteConnection.row(from: stmt, columnCount: columns.count))
            } else if step == SQLITE_DONE {
                break
            } else if step == SQLITE_INTERRUPT {
                return .failure(SQLDriverError.cancelled)
            } else {
                return .failure(SQLDriverError.sqlite(message: SQLiteConnection.errorMessage(from: db)))
            }
        }

        if isResultSet {
            return .success(QueryResult(columns: columns, rows: rows))
        }
        return .success(QueryResult(affectedRowCount: Int(sqlite3_changes(db))))
    }

    private func bind(_ parameters: [SQLValue], to stmt: OpaquePointer?) -> SQLDriverError? {
        for (index, value) in parameters.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(stmt, position)
            case .bool(let flag):
                status = sqlite3_bind_int(stmt, position, flag ? 1 : 0)
            case .int(let integer):
                status = sqlite3_bind_int64(stmt, position, integer)
            case .double(let double):
                status = sqlite3_bind_double(stmt, position, double)
            case .string(let string):
                status = sqlite3_bind_text(stmt, position, string, Int32(string.utf8.count), sqliteTransient)
            case .data(let data):
                status = sqlite3_bind_blob(stmt, position, (data as NSData).bytes, Int32(data.count), sqliteTransient)
            case .date(let date):
                let text = Self.dateFormatter.string(from: date)
                status = sqlite3_bind_text(stmt, position, text, Int32(text.utf8.count), sqliteTransient)
            }
            if status != SQLITE_OK {
                return .sqlite(message: "Failed to bind parameter \(index + 1): \(SQLiteConnection.errorMessage(from: db))")
            }
        }
        return nil
    }

    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct SQLiteStreamer {
    let db: OpaquePointer?
    let sql: String

    func run(continuation: RowStream.Continuation) {
        var stmt: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareStatus == SQLITE_OK, let stmt else {
            continuation.finish(throwing: SQLDriverError.sqlite(message: SQLiteConnection.errorMessage(from: db)))
            return
        }
        defer { sqlite3_finalize(stmt) }

        let columns = SQLiteConnection.columns(from: stmt)
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                continuation.yield(SQLiteConnection.row(from: stmt, columnCount: columns.count))
            } else if step == SQLITE_DONE {
                continuation.finish()
                return
            } else if step == SQLITE_INTERRUPT {
                continuation.finish(throwing: SQLDriverError.cancelled)
                return
            } else {
                continuation.finish(throwing: SQLDriverError.sqlite(message: SQLiteConnection.errorMessage(from: db)))
                return
            }
        }
    }
}
