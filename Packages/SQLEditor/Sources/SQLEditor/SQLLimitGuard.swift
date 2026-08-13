import Foundation

public struct SQLLimitGuard: Sendable {
    public static let defaultLimit = 1000

    public struct Outcome: Sendable, Equatable {
        public var sql: String
        public var didLimit: Bool

        public init(sql: String, didLimit: Bool) {
            self.sql = sql
            self.didLimit = didLimit
        }
    }

    public init() {}

    public func apply(_ sql: String, limit: Int = Self.defaultLimit) -> Outcome {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(sql: sql, didLimit: false)
        }
        let tokens = SQLLexer().tokenize(sql)
        guard isSelectOrWith(tokens) else {
            return Outcome(sql: sql, didLimit: false)
        }
        if hasTopLevelLimitOrFetch(tokens) {
            return Outcome(sql: sql, didLimit: false)
        }
        return Outcome(sql: appendLimit(sql, tokens: tokens, limit: limit), didLimit: true)
    }

    private func isSelectOrWith(_ tokens: [SQLToken]) -> Bool {
        for token in tokens {
            if token.kind == .whitespace || token.kind == .comment { continue }
            guard token.kind == .keyword else { return false }
            let word = token.text.uppercased()
            return word == "SELECT" || word == "WITH"
        }
        return false
    }

    private func hasTopLevelLimitOrFetch(_ tokens: [SQLToken]) -> Bool {
        var depth = 0
        for token in tokens {
            if token.text == "(" { depth += 1; continue }
            if token.text == ")" { depth = max(0, depth - 1); continue }
            if depth != 0 { continue }
            let word = token.text.uppercased()
            if word == "LIMIT" || word == "FETCH" { return true }
        }
        return false
    }

    private func appendLimit(_ sql: String, tokens: [SQLToken], limit: Int) -> String {
        let clause = " LIMIT \(limit)"
        let units = sql as NSString
        var insertAt = units.length
        if let last = tokens.last(where: { $0.kind != .whitespace }) {
            if last.text == ";" {
                insertAt = last.location
            } else {
                insertAt = last.location + last.length
            }
        }
        insertAt = min(max(insertAt, 0), units.length)
        return units.substring(to: insertAt) + clause + units.substring(from: insertAt)
    }
}
