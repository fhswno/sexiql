import Foundation

public enum StatementWriteGuard: Sendable {
    private static let sqlWrites: Set<String> = [
        "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "TRUNCATE",
        "GRANT", "REVOKE", "COPY", "CALL", "MERGE", "REPLACE", "LOAD",
        "VACUUM", "ANALYZE", "COMMENT", "REINDEX", "REFRESH", "DO",
    ]

    private static let redisWrites: Set<String> = [
        "SET", "SETEX", "SETNX", "MSET", "DEL", "UNLINK", "HSET", "HDEL",
        "LPUSH", "RPUSH", "LSET", "LREM", "SADD", "SREM", "ZADD", "ZREM",
        "EXPIRE", "PEXPIRE", "PERSIST", "RENAME", "FLUSHDB", "FLUSHALL",
    ]

    public static func isWrite(_ sql: String, kind: DatabaseKind) -> Bool {
        switch kind {
        case .redis:
            return isRedisWrite(sql)
        case .postgres, .mysql, .sqlite:
            return isSQLWrite(sql)
        }
    }

    private static func isRedisWrite(_ sql: String) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        let token = trimmed.split(whereSeparator: \.isWhitespace).first.map { String($0).uppercased() }
        return token.map { redisWrites.contains($0) } ?? false
    }

    private static func isSQLWrite(_ sql: String) -> Bool {
        let words = significantSQLWords(sql)
        guard let first = words.first else { return false }
        if sqlWrites.contains(first) { return true }
        if first == "WITH" {
            return words.contains { sqlWrites.contains($0) }
        }
        return false
    }

    private static func significantSQLWords(_ sql: String) -> [String] {
        var words: [String] = []
        var index = sql.startIndex
        while index < sql.endIndex {
            if sql[index].isWhitespace {
                index = sql.index(after: index)
                continue
            }
            if sql[index] == "-", sql.index(after: index) < sql.endIndex, sql[sql.index(after: index)] == "-" {
                guard let newline = sql[index...].firstIndex(of: "\n") else { break }
                index = sql.index(after: newline)
                continue
            }
            if sql[index] == "/", sql.index(after: index) < sql.endIndex, sql[sql.index(after: index)] == "*" {
                let rest = sql[sql.index(index, offsetBy: 2)...]
                guard let end = rest.range(of: "*/") else { break }
                index = end.upperBound
                continue
            }
            if sql[index] == "'" || sql[index] == "\"" {
                let quote = sql[index]
                index = sql.index(after: index)
                while index < sql.endIndex {
                    if sql[index] == quote {
                        index = sql.index(after: index)
                        break
                    }
                    index = sql.index(after: index)
                }
                continue
            }
            if sql[index].isLetter || sql[index] == "_" {
                let start = index
                while index < sql.endIndex, sql[index].isLetter || sql[index].isNumber || sql[index] == "_" {
                    index = sql.index(after: index)
                }
                words.append(sql[start..<index].uppercased())
                continue
            }
            index = sql.index(after: index)
        }
        return words
    }
}
