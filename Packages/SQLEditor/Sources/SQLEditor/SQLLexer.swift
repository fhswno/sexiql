import Foundation

public enum SQLTokenKind: Sendable, Equatable, Hashable {
    case keyword
    case identifier
    case parameter
    case string
    case number
    case comment
    case `operator`
    case punctuation
    case whitespace
}

public struct SQLToken: Sendable, Equatable {
    public var kind: SQLTokenKind
    public var text: String
    public var location: Int
    public var length: Int

    public init(kind: SQLTokenKind, text: String, location: Int, length: Int) {
        self.kind = kind
        self.text = text
        self.location = location
        self.length = length
    }
}

/// Tokenizer for SQL.
public struct SQLLexer: Sendable {
    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "DELETE",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "SEQUENCE", "SCHEMA",
        "DATABASE", "TRIGGER", "FUNCTION", "PROCEDURE", "JOIN", "LEFT", "RIGHT",
        "INNER", "OUTER", "FULL", "CROSS", "ON", "AND", "OR", "NOT", "NULL",
        "IS", "IN", "LIKE", "ILIKE", "BETWEEN", "DISTINCT", "ORDER", "BY",
        "GROUP", "HAVING", "LIMIT", "OFFSET", "AS", "PRIMARY", "KEY", "FOREIGN",
        "REFERENCES", "UNION", "ALL", "EXISTS", "CASE", "WHEN", "THEN", "ELSE",
        "END", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "SAVEPOINT", "WITH",
        "ASC", "DESC", "RETURNING", "CAST", "COALESCE", "COUNT", "SUM", "AVG",
        "MIN", "MAX", "EXPLAIN", "ANALYZE", "VACUUM", "PRAGMA", "USE", "IF",
        "CONSTRAINT", "UNIQUE", "CHECK", "DEFAULT", "AUTOINCREMENT", "BOOLEAN",
        "SET", "GRANT", "REVOKE", "TO", "ADD", "COLUMN", "RENAME", "TEMP",
    ]

    private static let twoCharOperators: Set<String> = [
        "==", ">=", "<=", "<>", "!=", "||", "&&", "::", ":=",
        "->", "<<", ">>", "~*", "!~", "!*", "~~", "#>", "#-", "..", "??",
    ]

    public init() {}

    public func tokenize(_ sql: String) -> [SQLToken] {
        let units = Array(sql.utf16)
        var tokens: [SQLToken] = []
        var i = 0
        let count = units.count

        while i < count {
            let unit = units[i]

            if Self.isWhitespace(unit) {
                let start = i
                while i < count && Self.isWhitespace(units[i]) { i += 1 }
                tokens.append(makeToken(.whitespace, units, start, i))
            } else if unit == 0x2D, i + 1 < count, units[i + 1] == 0x2D {
                let start = i
                i += 2
                while i < count && units[i] != 0x0A { i += 1 }
                tokens.append(makeToken(.comment, units, start, i))
            } else if unit == 0x2F, i + 1 < count, units[i + 1] == 0x2A {
                let start = i
                i += 2
                while i < count {
                    if units[i] == 0x2A, i + 1 < count, units[i + 1] == 0x2F {
                        i += 2
                        break
                    }
                    i += 1
                }
                tokens.append(makeToken(.comment, units, start, i))
            } else if unit == 0x27 {
                let start = i
                i += 1
                while i < count {
                    if units[i] == 0x27 {
                        if i + 1 < count, units[i + 1] == 0x27 {
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(makeToken(.string, units, start, i))
            } else if unit == 0x22 || unit == 0x60 {
                let start = i
                let quote = unit
                i += 1
                while i < count && units[i] != quote { i += 1 }
                if i < count { i += 1 }
                tokens.append(makeToken(.identifier, units, start, i))
            } else if unit == 0x5B {
                let start = i
                i += 1
                while i < count && units[i] != 0x5D { i += 1 }
                if i < count { i += 1 }
                tokens.append(makeToken(.identifier, units, start, i))
            } else if Self.isDigit(unit) || (unit == 0x2E && i + 1 < count && Self.isDigit(units[i + 1])) {
                let start = i
                i = scanNumber(units, from: i)
                tokens.append(makeToken(.number, units, start, i))
            } else if unit == 0x24, let delimiter = Self.dollarDelimiter(in: units, at: i) {
                let start = i
                var j = i + delimiter.length
                var end = units.count
                let closing = Array(delimiter.text.utf16)
                while j + closing.count <= units.count {
                    if Array(units[j..<(j + closing.count)]) == closing {
                        end = j + closing.count
                        break
                    }
                    j += 1
                }
                tokens.append(makeToken(.string, units, start, end))
                i = end
            } else if unit == 0x24, i + 1 < count, Self.isDigit(units[i + 1]) {
                let start = i
                i += 1
                while i < count && Self.isDigit(units[i]) { i += 1 }
                tokens.append(makeToken(.parameter, units, start, i))
            } else if Self.isIdentifierStart(unit) {
                let start = i
                while i < count && Self.isIdentifierPart(units[i]) { i += 1 }
                let text = String(decoding: units[start..<i], as: UTF16.self)
                let kind: SQLTokenKind = Self.keywords.contains(text.uppercased()) ? .keyword : .identifier
                tokens.append(SQLToken(kind: kind, text: text, location: start, length: i - start))
            } else {
                let start = i
                var length = 1
                if i + 1 < count {
                    let pair = String(decoding: [unit, units[i + 1]], as: UTF16.self)
                    if Self.twoCharOperators.contains(pair) {
                        length = 2
                    }
                }
                i += length
                let kind: SQLTokenKind = (length == 1 && Self.isPunctuation(unit)) ? .punctuation : .operator
                tokens.append(makeToken(kind, units, start, i))
            }
        }
        return tokens
    }

    private func makeToken(_ kind: SQLTokenKind, _ units: [UInt16], _ start: Int, _ end: Int) -> SQLToken {
        SQLToken(
            kind: kind,
            text: String(decoding: units[start..<end], as: UTF16.self),
            location: start,
            length: end - start
        )
    }

    private func scanNumber(_ units: [UInt16], from start: Int) -> Int {
        var i = start
        while i < units.count && Self.isDigit(units[i]) { i += 1 }
        if i < units.count, units[i] == 0x2E {
            i += 1
            while i < units.count && Self.isDigit(units[i]) { i += 1 }
        }
        if i < units.count, units[i] == 0x65 || units[i] == 0x45 {
            var j = i + 1
            if j < units.count, units[j] == 0x2B || units[j] == 0x2D { j += 1 }
            if j < units.count, Self.isDigit(units[j]) {
                while j < units.count && Self.isDigit(units[j]) { j += 1 }
                i = j
            }
        }
        return i
    }

    private static func dollarDelimiter(in units: [UInt16], at index: Int) -> (text: String, length: Int)? {
        guard units[index] == 0x24 else { return nil }
        var j = index + 1
        if j < units.count, isDigit(units[j]) { return nil }
        while j < units.count {
            let unit = units[j]
            if unit == 0x24 {
                return (String(decoding: units[index...j], as: UTF16.self), j - index + 1)
            }
            guard isIdentifierPart(unit) else { return nil }
            j += 1
        }
        return nil
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private static func isIdentifierStart(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F
    }

    private static func isIdentifierPart(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || isDigit(unit) || unit == 0x24 || unit == 0x40 || unit >= 0x80
    }

    private static func isPunctuation(_ unit: UInt16) -> Bool {
        unit == 0x28 || unit == 0x29 || unit == 0x5B || unit == 0x5D || unit == 0x2C || unit == 0x3B || unit == 0x2E
    }
}
