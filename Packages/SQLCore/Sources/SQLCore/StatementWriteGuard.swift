import Foundation

public enum StatementWriteGuard: Sendable {
    private static let sqlWrites: Set<String> = [
        "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP", "TRUNCATE",
        "GRANT", "REVOKE", "COPY", "CALL", "MERGE", "REPLACE", "LOAD",
        "VACUUM", "ANALYZE", "COMMENT", "REINDEX", "REFRESH", "DO",
        "RENAME", "FLUSH", "KILL", "SHUTDOWN", "PURGE", "INSTALL", "UNINSTALL",
        "IMPORT", "CLUSTER", "LOCK", "UNLOCK", "ATTACH",
    ]

    private static let redisWrites: Set<String> = [
        "SET", "SETEX", "SETNX", "PSETEX", "GETEX", "GETSET", "GETDEL", "SETRANGE", "SETBIT",
        "MSET", "MSETNX", "APPEND", "DEL", "UNLINK", "COPY", "MOVE", "RENAME", "RENAMENX",
        "INCR", "INCRBY", "INCRBYFLOAT", "DECR", "DECRBY",
        "HSET", "HSETNX", "HDEL", "HINCRBY", "HINCRBYFLOAT",
        "LPUSH", "LPUSHX", "RPUSH", "RPUSHX", "LSET", "LREM", "LINSERT", "LPOP", "RPOP", "LMOVE",
        "BLPOP", "BRPOP", "BRPOPLPUSH", "BLMOVE", "LMPOP", "BLMPOP", "LTRIM",
        "SADD", "SREM", "SPOP", "SMOVE", "SINTERSTORE", "SUNIONSTORE", "SDIFFSTORE",
        "ZADD", "ZREM", "ZINCRBY", "ZPOPMIN", "ZPOPMAX", "ZMPOP", "ZREMRANGEBYRANK",
        "ZREMRANGEBYSCORE", "ZREMRANGEBYLEX", "ZINTERSTORE", "ZUNIONSTORE", "ZDIFFSTORE",
        "ZRANGESTORE",
        "EXPIRE", "PEXPIRE", "EXPIREAT", "PEXPIREAT", "PERSIST", "TOUCH",
        "FLUSHDB", "FLUSHALL", "SWAPDB", "RESTORE", "RESTORE-ASKING", "MIGRATE",
        "XADD", "XDEL", "XTRIM", "XGROUP", "XSETID", "XACK", "XCLAIM", "XAUTOCLAIM",
        "XREADGROUP", "PFADD", "PFMERGE", "GEOADD", "GEOSEARCHSTORE", "BITOP", "BITFIELD",
        "EVAL", "EVALSHA", "FCALL", "SCRIPT", "FUNCTION",
        "CONFIG", "SHUTDOWN", "DEBUG", "SLAVEOF", "REPLICAOF", "FAILOVER", "ACL", "MODULE",
        "BGSAVE", "BGREWRITEAOF", "SAVE", "SLOWLOG", "LATENCY", "RESET", "EXEC",
    ]

    private static let redisReadSubcommands: [String: Set<String>] = [
        "CONFIG": ["GET"],
        "SLOWLOG": ["GET", "LEN"],
        "LATENCY": ["HISTORY", "GRAPH", "LATEST", "DOCTOR"],
        "ACL": ["WHOAMI", "USERS", "LIST", "GETUSER", "CAT"],
        "SCRIPT": ["EXISTS", "SHOW"],
        "FUNCTION": ["LIST", "DUMP", "STATS"],
        "CLUSTER": ["INFO", "MYID", "MYSHARDID", "SLOTS", "SHARDS", "NODES", "KEYSLOT",
                    "COUNTKEYSINSLOT", "GETKEYSINSLOT", "LINKS", "SLAVES", "REPLICAS"],
        "CLIENT": ["ID", "INFO", "LIST", "GETNAME"],
        "COMMAND": ["INFO", "COUNT", "GETKEYS", "LIST", "DOCS"],
    ]

    private static let redisWriteOptions: Set<String> = ["EX", "PX", "EXAT", "PXAT", "PERSIST"]

    public static func isWrite(_ sql: String, kind: DatabaseKind) -> Bool {
        switch kind {
        case .redis:
            return isRedisWrite(sql)
        case .postgres, .mysql, .sqlite:
            return isSQLWrite(sql, kind: kind)
        }
    }

    private static func isRedisWrite(_ sql: String) -> Bool {
        let tokens = sql.split(whereSeparator: \.isWhitespace).map { String($0).uppercased() }
        guard let command = tokens.first, !command.hasPrefix("#") else { return false }
        if command == "SORT" {
            return tokens.dropFirst().contains("STORE")
        }
        if command == "GETEX" {
            return !Set(tokens.dropFirst()).isDisjoint(with: redisWriteOptions)
        }
        if let readSubcommands = redisReadSubcommands[command] {
            guard let subcommand = tokens.dropFirst().first else { return true }
            return !readSubcommands.contains(subcommand)
        }
        return redisWrites.contains(command)
    }

    private static func isSQLWrite(_ sql: String, kind: DatabaseKind) -> Bool {
        let words = significantSQLWords(sql)
        guard let first = words.first else { return false }
        if sqlWrites.contains(first) { return true }
        if first == "WITH", words.contains(where: { sqlWrites.contains($0) }) {
            return true
        }
        if first == "EXPLAIN", words.contains("ANALYZE"),
           words.contains(where: { sqlWrites.contains($0) && $0 != "ANALYZE" }) {
            return true
        }

        if first == "SET" {
            let settingWords = Set(words.dropFirst())
            if !settingWords.isDisjoint(with: ["GLOBAL", "PERSIST", "PERSISTENT", "PASSWORD", "AUTHORIZATION", "SESSION_AUTHORIZATION", "DEFAULT"]) {
                return true
            }
            if settingWords.contains("DEFAULT_TRANSACTION_READ_ONLY") || settingWords.contains("TRANSACTION_READ_ONLY") {
                if !(settingWords.contains("ON") && !settingWords.contains("OFF") && !settingWords.contains("FALSE")) {
                    return true
                }
            }
            if settingWords.contains("TRANSACTION"), settingWords.contains("WRITE") {
                return true
            }
        }

        if first == "START" || first == "BEGIN", words.contains("WRITE") {
            return true
        }

        if first == "SELECT" || first == "WITH", words.contains("INTO") {
            switch kind {
            case .mysql:
                return words.contains("OUTFILE") || words.contains("DUMPFILE")
            case .postgres, .sqlite:
                return true
            case .redis:
                return false
            }
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
