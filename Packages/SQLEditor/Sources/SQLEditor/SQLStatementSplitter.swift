import Foundation

public struct SQLStatement: Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}


public struct SQLStatementSplitter: Sendable {
    public init() {}

    public func split(_ sql: String) -> [SQLStatement] {
        let tokens = SQLLexer().tokenize(sql)
        var statements: [SQLStatement] = []
        var start = 0
        for token in tokens where token.text == ";" {
            appendRange(sql, start..<token.location, to: &statements)
            start = token.location + 1
        }
        appendRange(sql, start..<Array(sql.utf16).count, to: &statements)
        return statements
    }

    private func appendRange(_ sql: String, _ range: Range<Int>, to statements: inout [SQLStatement]) {
        guard range.lowerBound < range.upperBound else { return }
        let units = Array(sql.utf16)
        let trimmed = String(decoding: units[range], as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        statements.append(SQLStatement(text: trimmed))
    }
}
