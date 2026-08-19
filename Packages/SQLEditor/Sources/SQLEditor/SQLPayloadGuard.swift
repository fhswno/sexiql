import Foundation

public enum SQLPayloadGuard: Sendable {
    public static let extraStarters: Set<String> = [
        "COPY", "TRUNCATE", "TABLE", "VALUES", "DO", "CALL", "SHOW", "LISTEN", "NOTIFY",
        "UNLISTEN", "LOAD", "RESET", "REFRESH", "LOCK", "PREPARE", "EXECUTE", "DEALLOCATE",
        "COMMENT", "CHECKPOINT", "DISCARD", "CLUSTER", "REINDEX", "DECLARE", "FETCH",
        "MOVE", "CLOSE", "REPLACE", "MERGE", "ATTACH", "DETACH",
    ]

    public static func looksLikeSQL(_ sql: String) -> Bool {
        let tokens = SQLLexer().tokenize(sql)
        for token in tokens {
            if token.kind == .whitespace || token.kind == .comment { continue }
            if token.kind == .keyword { return true }
            if token.text == "(" { return true }
            if extraStarters.contains(token.text.uppercased()) { return true }
            return false
        }
        return false
    }
}
