import XCTest
@testable import SQLEditor

final class LexerTests: XCTestCase {
    private let lexer = SQLLexer()

    private func kinds(_ sql: String) -> [SQLTokenKind] {
        lexer.tokenize(sql).map(\.kind)
    }

    func testBasicSelect() {
        let tokens = lexer.tokenize("SELECT * FROM users WHERE id = 42;")
        XCTAssertEqual(tokens.map(\.text), ["SELECT", " ", "*", " ", "FROM", " ", "users", " ", "WHERE", " ", "id", " ", "=", " ", "42", ";"])
        XCTAssertEqual(kinds("SELECT * FROM users WHERE id = 42;"), [
            .keyword, .whitespace, .operator, .whitespace, .keyword, .whitespace,
            .identifier, .whitespace, .keyword, .whitespace, .identifier, .whitespace,
            .operator, .whitespace, .number, .punctuation,
        ])
    }

    func testKeywordsAreCaseInsensitive() {
        let tokens = lexer.tokenize("select * from users")
        XCTAssertEqual(tokens.first?.kind, .keyword)
        XCTAssertEqual(tokens.first?.text, "select")
        XCTAssertTrue(tokens.contains { $0.text == "from" && $0.kind == .keyword })
    }

    func testStringLiteralsWithEscapes() {
        let tokens = lexer.tokenize("SELECT 'it''s fine'")
        XCTAssertEqual(tokens.last?.kind, .string)
        XCTAssertEqual(tokens.last?.text, "'it''s fine'")
    }

    func testUnterminatedString() {
        let tokens = lexer.tokenize("SELECT 'oops")
        XCTAssertEqual(tokens.last?.kind, .string)
        XCTAssertEqual(tokens.last?.text, "'oops")
    }

    func testLineComment() {
        let tokens = lexer.tokenize("SELECT 1 -- note\nFROM t")
        XCTAssertEqual(tokens.map(\.kind), [
            .keyword, .whitespace, .number, .whitespace, .comment, .whitespace,
            .keyword, .whitespace, .identifier,
        ])
        XCTAssertEqual(tokens[4].text, "-- note")
    }

    func testBlockComment() {
        let tokens = lexer.tokenize("SELECT /* multi\nline */ 1")
        XCTAssertTrue(tokens.contains { $0.kind == .comment && $0.text == "/* multi\nline */" })
    }

    func testQuotedIdentifiers() {
        XCTAssertEqual(lexer.tokenize("\"My Table\"").first?.kind, .identifier)
        XCTAssertEqual(lexer.tokenize("`col`").first?.kind, .identifier)
        XCTAssertEqual(lexer.tokenize("[col]").first?.kind, .identifier)
    }

    func testRedisHashCommentAndKeywords() {
        let lexer = SQLLexer(dialect: .redis)
        let tokens = lexer.tokenize("GET foo # comment")
        XCTAssertEqual(tokens.first?.kind, .keyword)
        XCTAssertEqual(tokens.first?.text, "GET")
        XCTAssertTrue(tokens.contains { $0.kind == .comment && $0.text == "# comment" })
    }

    func testRedisDoesNotTreatDashDashAsComment() {
        let lexer = SQLLexer(dialect: .redis)
        let tokens = lexer.tokenize("GET foo--bar")
        XCTAssertFalse(tokens.contains { $0.kind == .comment })
    }

    func testRedisQuotedString() {
        let lexer = SQLLexer(dialect: .redis)
        let tokens = lexer.tokenize("SET foo \"hello world\"")
        XCTAssertTrue(tokens.contains { $0.kind == .string && $0.text == "\"hello world\"" })
    }

    func testNumbers() {
        XCTAssertEqual(kinds("3.14"), [.number])
        XCTAssertEqual(kinds("1e10"), [.number])
        XCTAssertEqual(kinds("2.5E-3"), [.number])
        XCTAssertEqual(kinds(".5"), [.number])
        XCTAssertEqual(lexer.tokenize("1e10").first?.text, "1e10")
    }

    func testParameters() {
        XCTAssertEqual(kinds("$1"), [.parameter])
        XCTAssertEqual(lexer.tokenize("$12").first?.text, "$12")
        XCTAssertEqual(kinds("$x"), [.operator, .identifier])
    }

    func testUnicodeIdentifiersAndStrings() {
        XCTAssertEqual(lexer.tokenize("café").first?.kind, .identifier)
        let emoji = lexer.tokenize("SELECT '😀'")
        XCTAssertEqual(emoji.last?.kind, .string)
        XCTAssertEqual(emoji.last?.text, "'😀'")
    }

    func testOffsetsMatchUTF16Length() {
        let sql = "SELECT 'é' FROM t"
        let tokens = lexer.tokenize(sql)
        for token in tokens {
            XCTAssertEqual(token.length, Array(token.text.utf16).count)
            let start = sql.utf16.index(sql.utf16.startIndex, offsetBy: token.location)
            let end = sql.utf16.index(start, offsetBy: token.length)
            XCTAssertEqual(String(sql.utf16[start..<end]), token.text)
        }
    }

    func testDollarQuotedStrings() {
        XCTAssertEqual(lexer.tokenize("$$abc; $$").first?.kind, .string)
        XCTAssertEqual(lexer.tokenize("$$abc; $$").first?.text, "$$abc; $$")
        let tagged = lexer.tokenize("$body$ SELECT 1; INSERT INTO t; $body$")
        XCTAssertEqual(tagged.first?.kind, .string)
        XCTAssertEqual(tagged.first?.text, "$body$ SELECT 1; INSERT INTO t; $body$")
        let unclosed = lexer.tokenize("SELECT $$ oops")
        XCTAssertEqual(unclosed.last?.kind, .string)
        XCTAssertEqual(unclosed.last?.text, "$$ oops")
    }

    func testDollarQuoteDoesNotSwallowParameters() {
        XCTAssertEqual(kinds("$1"), [.parameter])
        XCTAssertEqual(lexer.tokenize("SELECT $x").map(\.text), ["SELECT", " ", "$", "x"])
    }

    func testOperatorsAndPunctuation() {
        XCTAssertEqual(kinds("a.b"), [.identifier, .punctuation, .identifier])
        XCTAssertEqual(kinds("a >= b"), [.identifier, .whitespace, .operator, .whitespace, .identifier])
        XCTAssertEqual(lexer.tokenize(">=").first?.text, ">=")
    }
}
