import Foundation

enum RedisResultGrid: Sendable {
    static func queryResult(for reply: RedisReply, command: [String]) throws -> QueryResult {
        if case .error(let message) = reply {
            throw RedisError.serverError(message)
        }
        let verb = command.first?.uppercased() ?? ""
        if verb == "SCAN", case .array(let items) = reply, let items, items.count >= 2 {
            return scanResult(items)
        }
        if isWrite(verb), !showsWriteValue(verb) {
            return QueryResult(affectedRowCount: affectedCount(reply))
        }
        switch reply {
        case .status(let text):
            return QueryResult(
                columns: [column("status", type: "status", ordinal: 0)],
                rows: [SQLRow(values: [.string(text)])]
            )
        case .integer(let value):
            return QueryResult(
                columns: [column("value", type: "integer", ordinal: 0)],
                rows: [SQLRow(values: [.int(value)])]
            )
        case .bulk(let data):
            return QueryResult(
                columns: [column("value", type: "bulk", ordinal: 0)],
                rows: [SQLRow(values: [bulkValue(data)])]
            )
        case .array(let items):
            return arrayResult(items ?? [], command: command)
        case .error:
            throw RedisError.serverError("Redis error")
        }
    }

    static func keyLoadCommand(type: String, key: String) -> String {
        let quoted = RedisCommand.quote(key)
        switch type.lowercased() {
        case "hash": return "HGETALL \(quoted)"
        case "list": return "LRANGE \(quoted) 0 -1"
        case "set": return "SMEMBERS \(quoted)"
        case "zset": return "ZRANGE \(quoted) 0 -1 WITHSCORES"
        case "stream": return "XRANGE \(quoted) - +"
        default: return "GET \(quoted)"
        }
    }

    private static func scanResult(_ items: [RedisReply]) -> QueryResult {
        let keys = items[1].arrayValues
        return QueryResult(
            columns: [column("key", type: "bulk", ordinal: 0)],
            rows: keys.map { SQLRow(values: [bulkValue($0)]) }
        )
    }

    private static func arrayResult(_ items: [RedisReply], command: [String]) -> QueryResult {
        let verb = command.first?.uppercased() ?? ""
        if verb == "HGETALL" || (verb == "ZRANGE" && command.contains { $0.uppercased() == "WITHSCORES" }) {
            return pairs(items, left: verb == "HGETALL" ? "field" : "member", right: verb == "HGETALL" ? "value" : "score")
        }
        if verb == "LRANGE" {
            return QueryResult(
                columns: [
                    column("index", type: "integer", ordinal: 0),
                    column("value", type: "bulk", ordinal: 1),
                ],
                rows: items.enumerated().map { index, item in
                    SQLRow(values: [.int(Int64(index)), item.sqlValue])
                }
            )
        }
        if items.allSatisfy({ $0.isArray }) {
            let width = items.map { $0.arrayValues.count }.max() ?? 0
            let columns = (0..<max(width, 1)).map { column("value_\($0)", type: "bulk", ordinal: $0) }
            let rows = items.map { item in
                var values = item.arrayValues.map(bulkValue)
                while values.count < columns.count { values.append(.null) }
                return SQLRow(values: values)
            }
            return QueryResult(columns: columns, rows: rows)
        }
        return QueryResult(
            columns: [column("value", type: "bulk", ordinal: 0)],
            rows: items.map { SQLRow(values: [$0.sqlValue]) }
        )
    }

    private static func pairs(_ items: [RedisReply], left: String, right: String) -> QueryResult {
        var rows: [SQLRow] = []
        var index = 0
        while index + 1 < items.count {
            rows.append(SQLRow(values: [items[index].sqlValue, items[index + 1].sqlValue]))
            index += 2
        }
        if index < items.count {
            rows.append(SQLRow(values: [items[index].sqlValue, .null]))
        }
        return QueryResult(
            columns: [column(left, type: "bulk", ordinal: 0), column(right, type: "bulk", ordinal: 1)],
            rows: rows
        )
    }

    private static func isWrite(_ verb: String) -> Bool {
        ["SET", "SETEX", "SETNX", "MSET", "DEL", "UNLINK", "HSET", "HDEL", "LPUSH", "RPUSH", "LSET", "LREM",
         "SADD", "SREM", "ZADD", "ZREM", "EXPIRE", "PEXPIRE", "PERSIST", "RENAME", "FLUSHDB", "FLUSHALL",
         "SELECT", "AUTH"].contains(verb)
    }

    private static func showsWriteValue(_ verb: String) -> Bool {
        ["INCR", "INCRBY", "DECR", "DECRBY", "INCRBYFLOAT"].contains(verb)
    }

    private static func affectedCount(_ reply: RedisReply) -> Int {
        switch reply {
        case .integer(let value): Int(value)
        case .status: 1
        default: 1
        }
    }

    private static func column(_ name: String, type: String, ordinal: Int) -> SQLColumn {
        SQLColumn(name: name, dataType: type, ordinal: ordinal)
    }

    private static func bulkValue(_ data: Data?) -> SQLValue {
        guard let data else { return .null }
        if let text = String(data: data, encoding: .utf8) {
            return .string(text)
        }
        return .data(data)
    }
}

private extension RedisReply {
    var isArray: Bool {
        if case .array = self { return true }
        return false
    }

    var arrayValues: [Data?] {
        switch self {
        case .array(let items):
            return (items ?? []).map(\.bulkData)
        default:
            return [bulkData]
        }
    }

    var bulkData: Data? {
        switch self {
        case .bulk(let data): data
        case .status(let text): Data(text.utf8)
        case .integer(let value): Data(String(value).utf8)
        default: nil
        }
    }

    var sqlValue: SQLValue {
        switch self {
        case .status(let text):
            return SQLValue.string(text)
        case .integer(let value):
            return SQLValue.int(value)
        case .bulk(let data):
            if let data, let text = String(data: data, encoding: .utf8) {
                return SQLValue.string(text)
            }
            return data.map { SQLValue.data($0) } ?? .null
        case .array(let items):
            let joined = (items ?? []).compactMap(\.string).joined(separator: ",")
            return SQLValue.string(joined)
        case .error(let text):
            return SQLValue.string(text)
        }
    }
}
