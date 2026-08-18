import Foundation

public struct SQLFormatter: Sendable {
    public var indentUnit: String

    public init(indentUnit: String = "  ") {
        self.indentUnit = indentUnit
    }

    public func format(_ sql: String, dialect: EditorDialect = .sql) -> String {
        if dialect == .redis { return sql }
        let tokens = SQLLexer().tokenize(sql)
        var out = ""
        var i = 0
        var paren = 0
        var indent = 0
        var atLineStart = true
        var selectDepth: Int?
        var whereDepth: Int?
        var tight = false

        func peekSignificant(_ from: Int) -> SQLToken? {
            var j = from
            while j < tokens.count {
                if tokens[j].kind != .whitespace { return tokens[j] }
                j += 1
            }
            return nil
        }

        func skipWhitespace() {
            while i < tokens.count, tokens[i].kind == .whitespace { i += 1 }
        }

        func newline(_ extra: Int = 0) {
            let level = max(0, indent + extra)
            if out.isEmpty {
                atLineStart = true
                return
            }
            while out.hasSuffix(" ") { out.removeLast() }
            out += "\n" + String(repeating: indentUnit, count: level)
            atLineStart = true
        }

        func space() {
            if tight {
                tight = false
                return
            }
            if atLineStart || out.isEmpty || out.hasSuffix(" ") || out.hasSuffix("\n") || out.hasSuffix("(") {
                return
            }
            if let last = out.last, ".,;".contains(last) { return }
            out += " "
        }

        func emit(_ text: String) {
            out += text
            atLineStart = false
        }

        func isClause(_ word: String) -> Bool {
            [
                "SELECT", "FROM", "WHERE", "HAVING", "LIMIT", "OFFSET", "UNION",
                "EXCEPT", "INTERSECT", "INSERT", "VALUES", "UPDATE", "SET",
                "DELETE", "CREATE", "ALTER", "DROP", "WITH", "RETURNING",
                "GROUP", "ORDER", "JOIN", "USING",
            ].contains(word)
        }

        func joinPrefix(_ word: String) -> Bool {
            ["LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "NATURAL"].contains(word)
        }

        while i < tokens.count {
            skipWhitespace()
            guard i < tokens.count else { break }
            let token = tokens[i]

            if token.kind == .comment {
                if !atLineStart { space() }
                emit(token.text.trimmingCharacters(in: .whitespaces))
                newline()
                i += 1
                continue
            }

            if token.text == ";" {
                emit(";")
                indent = 0
                selectDepth = nil
                whereDepth = nil
                i += 1
                skipWhitespace()
                if i < tokens.count {
                    out += "\n\n"
                    atLineStart = true
                }
                continue
            }

            if token.text == "(" {
                emit("(")
                paren += 1
                i += 1
                if let next = peekSignificant(i), next.kind == .keyword, next.text.uppercased() == "SELECT" {
                    indent += 1
                    newline()
                }
                continue
            }

            if token.text == ")" {
                if paren > 0 { paren -= 1 }
                if selectDepth == paren + 1 { selectDepth = nil }
                if whereDepth == paren + 1 { whereDepth = nil }
                if out.hasSuffix("\n") || atLineStart {
                    indent = max(0, indent - 1)
                    while out.hasSuffix(" ") { out.removeLast() }
                    if !out.hasSuffix("\n") { out += "\n" }
                    out += String(repeating: indentUnit, count: indent)
                }
                emit(")")
                i += 1
                continue
            }

            if token.text == "," {
                emit(",")
                i += 1
                if let depth = selectDepth, paren == depth {
                    newline(1)
                } else if paren > 0 {
                    space()
                } else {
                    space()
                }
                continue
            }

            if token.kind == .keyword {
                var word = token.text.uppercased()
                i += 1

                if joinPrefix(word) {
                    var parts = [word]
                    skipWhitespace()
                    if i < tokens.count, tokens[i].kind == .keyword, tokens[i].text.uppercased() == "OUTER" {
                        parts.append("OUTER")
                        i += 1
                        skipWhitespace()
                    }
                    if i < tokens.count, tokens[i].kind == .keyword, tokens[i].text.uppercased() == "JOIN" {
                        parts.append("JOIN")
                        i += 1
                        word = parts.joined(separator: " ")
                    }
                } else if word == "GROUP" || word == "ORDER" {
                    skipWhitespace()
                    if i < tokens.count, tokens[i].kind == .keyword, tokens[i].text.uppercased() == "BY" {
                        word = word + " BY"
                        i += 1
                    }
                } else if word == "INSERT" {
                    skipWhitespace()
                    if i < tokens.count, tokens[i].kind == .keyword, tokens[i].text.uppercased() == "INTO" {
                        word = "INSERT INTO"
                        i += 1
                    }
                }

                let clause = isClause(word) || word.hasSuffix(" JOIN") || word == "GROUP BY" || word == "ORDER BY" || word == "INSERT INTO"
                if clause {
                    if word == "SELECT" {
                        selectDepth = paren
                        if paren == 0 { indent = 0 }
                    }
                    if word == "WHERE" || word == "HAVING" || word == "ON" {
                        whereDepth = paren
                    }
                    if word == "FROM" || word == "JOIN" || word.hasSuffix(" JOIN") {
                        if selectDepth == paren { selectDepth = nil }
                    }
                    newline()
                    emit(word)
                    if word == "SELECT", selectListHasComma(from: i, depth: paren, tokens: tokens) {
                        newline(1)
                    }
                    continue
                }

                if (word == "AND" || word == "OR"), let depth = whereDepth, paren == depth {
                    newline(1)
                    emit(word)
                    continue
                }

                space()
                emit(word)
                continue
            }

            if token.kind == .operator {
                let glued = ["::", "->", "->>", "#>", "#>>", "||"]
                if glued.contains(token.text) {
                    emit(token.text)
                    tight = true
                } else {
                    space()
                    emit(token.text)
                    space()
                }
                i += 1
                continue
            }

            if token.kind == .punctuation, token.text == "." {
                emit(".")
                tight = true
                i += 1
                continue
            }

            space()
            emit(token.text)
            i += 1
        }

        while out.hasSuffix("\n") || out.hasSuffix(" ") { out.removeLast() }
        if !out.isEmpty { out += "\n" }
        return out
    }

    private func selectListHasComma(from start: Int, depth: Int, tokens: [SQLToken]) -> Bool {
        var j = start
        var paren = depth
        while j < tokens.count {
            let token = tokens[j]
            if token.kind == .whitespace {
                j += 1
                continue
            }
            if token.text == "(" { paren += 1; j += 1; continue }
            if token.text == ")" {
                if paren == depth { return false }
                paren -= 1
                j += 1
                continue
            }
            if token.text == ",", paren == depth { return true }
            if token.kind == .keyword, paren == depth {
                let word = token.text.uppercased()
                if ["FROM", "WHERE", "INTO", "UNION", "EXCEPT", "INTERSECT", "LIMIT"].contains(word) {
                    return false
                }
            }
            if token.text == ";" { return false }
            j += 1
        }
        return false
    }
}
