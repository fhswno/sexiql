import XCTest
@testable import SQLEditor

final class StatementSplitterTests: XCTestCase {
    private let splitter = SQLStatementSplitter()

    func testMultipleStatements() {
        let statements = splitter.split("SELECT 1; SELECT 2; SELECT 3")
        XCTAssertEqual(statements.map(\.text), ["SELECT 1", "SELECT 2", "SELECT 3"])
    }

    func testSemicolonsInsideStringsIgnored() {
        let statements = splitter.split("INSERT INTO t VALUES ('a;b'); SELECT 1;")
        XCTAssertEqual(statements.map(\.text), ["INSERT INTO t VALUES ('a;b')", "SELECT 1"])
    }

    func testSemicolonsInsideCommentsIgnored() {
        let statements = splitter.split("SELECT 1; -- note; here\nSELECT 2; /* block; */ SELECT 3")
        XCTAssertEqual(statements.map(\.text), ["SELECT 1", "-- note; here\nSELECT 2", "/* block; */ SELECT 3"])
    }

    func testSemicolonsInsideDollarQuotesIgnored() {
        let statements = splitter.split("CREATE FUNCTION f() RETURNS void AS $$ BEGIN EXECUTE 'SELECT 1;'; END; $$ LANGUAGE plpgsql; SELECT 2;")
        XCTAssertEqual(statements.count, 2)
        XCTAssertTrue(statements[0].text.hasPrefix("CREATE FUNCTION"))
        XCTAssertEqual(statements[1].text, "SELECT 2")
    }

    func testWhitespaceTrimmed() {
        let statements = splitter.split("  SELECT 1 ;  \n SELECT 2; ")
        XCTAssertEqual(statements.map(\.text), ["SELECT 1", "SELECT 2"])
    }

    func testEmptyInput() {
        XCTAssertEqual(splitter.split("").count, 0)
        XCTAssertEqual(splitter.split("   ").count, 0)
        XCTAssertEqual(splitter.split("; ; ;").count, 0)
    }

    func testSingleStatementWithoutSemicolon() {
        XCTAssertEqual(splitter.split("SELECT 1").map(\.text), ["SELECT 1"])
    }

    func testJSONOperatorAndComparisonStayOneStatement() {
        let sql = """
        SELECT id, state, created_at, started_at, completed_at, tracking_id
        FROM q_events
        WHERE event = 'Nightly Sync > Client'
          AND input->>'client' = 'ironclad'
        ORDER BY created_at DESC
        LIMIT 10
        """
        let statements = splitter.split(sql)
        XCTAssertEqual(statements.count, 1)
        XCTAssertTrue(statements[0].text.contains("->>'client'"))
        XCTAssertTrue(statements[0].text.contains("Nightly Sync > Client"))
    }
}

final class SyntaxRoleTests: XCTestCase {
    func testRoleMapping() {
        XCTAssertEqual(SyntaxRoleMapping.role(for: .keyword), .keyword)
        XCTAssertEqual(SyntaxRoleMapping.role(for: .string), .string)
        XCTAssertEqual(SyntaxRoleMapping.role(for: .number), .number)
        XCTAssertEqual(SyntaxRoleMapping.role(for: .comment), .comment)
        XCTAssertEqual(SyntaxRoleMapping.role(for: .identifier), .identifier)
        XCTAssertEqual(SyntaxRoleMapping.role(for: .parameter), .parameter)
        XCTAssertEqual(SyntaxRoleMapping.role(for: .operator), .other)
        XCTAssertEqual(SyntaxRoleMapping.role(for: .whitespace), .other)
    }
}
