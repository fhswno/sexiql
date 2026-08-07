import XCTest
@testable import SQLCore

final class ChatMarkdownTests: XCTestCase {
    func testParagraphAndInlineFenceSplit() {
        let text = """
        Hello **world**.

        ```sql
        SELECT 1;
        ```

        Done.
        """
        let blocks = ChatMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 3)
        guard case .paragraph(let p1) = blocks[0] else { return XCTFail("p0") }
        XCTAssertTrue(p1.contains("Hello"))
        guard case .code(let lang, let code) = blocks[1] else { return XCTFail("code") }
        XCTAssertEqual(lang, "sql")
        XCTAssertEqual(code, "SELECT 1;")
        guard case .paragraph(let p2) = blocks[2] else { return XCTFail("p2") }
        XCTAssertTrue(p2.contains("Done"))
    }

    func testUnclosedFenceStreaming() {
        let text = "Intro\n\n```sql\nSELECT *\nFROM t"
        let blocks = ChatMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 2)
        guard case .code(let lang, let code) = blocks[1] else { return XCTFail("code") }
        XCTAssertEqual(lang, "sql")
        XCTAssertTrue(code.contains("SELECT *"))
        XCTAssertTrue(code.contains("FROM t"))
    }

    func testUnorderedList() {
        let text = """
        Notes:

        * one
        * two
        * three
        """
        let blocks = ChatMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 2)
        guard case .list(let ordered, let items) = blocks[1] else { return XCTFail("list") }
        XCTAssertFalse(ordered)
        XCTAssertEqual(items, ["one", "two", "three"])
    }

    func testOrderedList() {
        let text = "1. alpha\n2. beta"
        let blocks = ChatMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let ordered, let items) = blocks[0] else { return XCTFail("list") }
        XCTAssertTrue(ordered)
        XCTAssertEqual(items, ["alpha", "beta"])
    }

    func testSQLInsertable() {
        XCTAssertTrue(ChatMarkdownParser.isSQLInsertable(language: "sql", code: "x"))
        XCTAssertTrue(ChatMarkdownParser.isSQLInsertable(language: "PostgreSQL", code: "x"))
        XCTAssertTrue(ChatMarkdownParser.isSQLInsertable(language: nil, code: "SELECT 1"))
        XCTAssertTrue(ChatMarkdownParser.isSQLInsertable(language: nil, code: "insert into t values (1)"))
        XCTAssertFalse(ChatMarkdownParser.isSQLInsertable(language: "swift", code: "let x = 1"))
        XCTAssertFalse(ChatMarkdownParser.isSQLInsertable(language: nil, code: "hello world"))
    }

    func testEmptyAndPlain() {
        XCTAssertTrue(ChatMarkdownParser.parse("").isEmpty)
        let blocks = ChatMarkdownParser.parse("just text")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let p) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(p, "just text")
    }

    func testFenceLanguageTrim() {
        let text = "```  mysql  \nSELECT 1\n```"
        let blocks = ChatMarkdownParser.parse(text)
        guard case .code(let lang, let code) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(lang, "mysql")
        XCTAssertEqual(code, "SELECT 1")
    }

    func testMultipleCodeBlocks() {
        let text = """
        ```sql
        A
        ```
        mid
        ```
        B
        ```
        """
        let blocks = ChatMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 3)
        guard case .code(let l1, let c1) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(l1, "sql")
        XCTAssertEqual(c1, "A")
        guard case .paragraph(let p) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(p, "mid")
        guard case .code(let l2, let c2) = blocks[2] else { return XCTFail() }
        XCTAssertNil(l2)
        XCTAssertEqual(c2, "B")
    }
}
