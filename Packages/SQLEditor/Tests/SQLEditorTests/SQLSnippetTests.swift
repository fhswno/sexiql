import AppKit
import XCTest
@testable import SQLEditor

final class SQLSnippetTests: XCTestCase {
    func testNoSelectionReturnsFullText() {
        let full = "SELECT 1;\nSELECT 2;"
        let result = SQLEditorTextView.sqlToRun(
            fullText: full,
            selectedRange: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(result, full)
    }

    func testSelectionReturnsOnlySelectedSQL() {
        let full = "SELECT * FROM users\nLIMIT 3;\n\nINSERT INTO users VALUES (1);"
        let selectSQL = "SELECT * FROM users\nLIMIT 3;"
        let ns = full as NSString
        let range = ns.range(of: selectSQL)
        XCTAssertNotEqual(range.location, NSNotFound)
        let result = SQLEditorTextView.sqlToRun(fullText: full, selectedRange: range)
        XCTAssertEqual(result, selectSQL)
    }

    func testWhitespaceOnlySelectionFallsBackToFull() {
        let withSpace = "SELECT 1;\n\n"
        let spaceRange = (withSpace as NSString).range(of: "\n\n")
        let fallback = SQLEditorTextView.sqlToRun(fullText: withSpace, selectedRange: spaceRange)
        XCTAssertEqual(fallback, withSpace)
    }

    func testOutOfBoundsSelectionFallsBackToFull() {
        let full = "SELECT 1;"
        let result = SQLEditorTextView.sqlToRun(
            fullText: full,
            selectedRange: NSRange(location: 100, length: 5)
        )
        XCTAssertEqual(result, full)
    }
}
