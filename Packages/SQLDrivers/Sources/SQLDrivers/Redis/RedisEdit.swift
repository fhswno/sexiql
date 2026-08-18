import Foundation

public enum RedisEdit: Sendable {
    public static let schemaPrefix = "redis:"

    public static func table(forCommand tokens: [String], columns: [SQLColumn]) -> EditableTable? {
        guard let verb = tokens.first?.uppercased(), tokens.count >= 2 else { return nil }
        let key = tokens[1]
        let names = columns.map(\.name)
        switch verb {
        case "GET", "GETDEL", "GETEX":
            return EditableTable(name: key, columns: names.isEmpty ? ["value"] : names, primaryKey: ["value"], schema: schemaPrefix + "string")
        case "HGETALL", "HGET":
            return EditableTable(name: key, columns: names.isEmpty ? ["field", "value"] : names, primaryKey: ["field"], schema: schemaPrefix + "hash")
        case "LRANGE", "LINDEX":
            return EditableTable(name: key, columns: names.isEmpty ? ["index", "value"] : names, primaryKey: ["index"], schema: schemaPrefix + "list")
        case "SMEMBERS", "SSCAN":
            return EditableTable(name: key, columns: names.isEmpty ? ["member"] : names, primaryKey: names.first.map { [$0] } ?? ["member"], schema: schemaPrefix + "set")
        case "ZRANGE", "ZSCAN":
            return EditableTable(name: key, columns: names.isEmpty ? ["member", "score"] : names, primaryKey: ["member"], schema: schemaPrefix + "zset")
        default:
            return nil
        }
    }

    public static func isRedisTable(_ table: EditableTable) -> Bool {
        table.schema?.hasPrefix(schemaPrefix) == true
    }

    public static func redisType(_ table: EditableTable) -> String {
        String(table.schema?.dropFirst(schemaPrefix.count) ?? "string")
    }

    public static func updateCommand(
        table: EditableTable,
        column: Int,
        newValue: SQLValue,
        primaryKeyValues: [SQLValue]
    ) -> String? {
        let kind = redisType(table)
        let key = table.name
        switch kind {
        case "string":
            return RedisCommand.line(["SET", key, string(newValue)])
        case "hash":
            guard column == 1 || table.columns.indices.contains(column) && table.columns[column] == "value" else { return nil }
            let field = string(primaryKeyValues.first)
            return RedisCommand.line(["HSET", key, field, string(newValue)])
        case "list":
            let index = string(primaryKeyValues.first)
            return RedisCommand.line(["LSET", key, index, string(newValue)])
        case "zset":
            if table.columns.indices.contains(column), table.columns[column] == "score" || column == 1 {
                let member = string(primaryKeyValues.first)
                return RedisCommand.line(["ZADD", key, string(newValue), member])
            }
            return nil
        default:
            return nil
        }
    }

    public static func deleteCommand(table: EditableTable, primaryKeyValues: [SQLValue]) -> String? {
        let kind = redisType(table)
        let key = table.name
        switch kind {
        case "string":
            return RedisCommand.line(["DEL", key])
        case "hash":
            return RedisCommand.line(["HDEL", key, string(primaryKeyValues.first)])
        case "set":
            return RedisCommand.line(["SREM", key, string(primaryKeyValues.first)])
        case "zset":
            return RedisCommand.line(["ZREM", key, string(primaryKeyValues.first)])
        default:
            return nil
        }
    }

    public static func insertCommand(table: EditableTable, columns: [String], values: [SQLValue]) -> String? {
        let kind = redisType(table)
        let key = table.name
        func value(named name: String) -> SQLValue {
            guard let index = columns.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
                  values.indices.contains(index) else { return .null }
            return values[index]
        }
        switch kind {
        case "string":
            return RedisCommand.line(["SET", key, string(value(named: "value"))])
        case "hash":
            return RedisCommand.line(["HSET", key, string(value(named: "field")), string(value(named: "value"))])
        case "list":
            return RedisCommand.line(["RPUSH", key, string(value(named: "value"))])
        case "set":
            return RedisCommand.line(["SADD", key, string(value(named: "member"))])
        case "zset":
            return RedisCommand.line(["ZADD", key, string(value(named: "score")), string(value(named: "member"))])
        default:
            return nil
        }
    }

    private static func string(_ value: SQLValue?) -> String {
        switch value {
        case .none, .null: ""
        case .string(let text): text
        case .int(let number): String(number)
        case .double(let number): String(number)
        case .bool(let flag): flag ? "1" : "0"
        case .data(let data): String(data: data, encoding: .utf8) ?? ""
        case .date(let date): ISO8601DateFormatter().string(from: date)
        }
    }
}
