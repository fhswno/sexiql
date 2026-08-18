import XCTest
@testable import SQLEditor

final class SQLFormatterTests: XCTestCase {
    private let formatter = SQLFormatter()

    func testUppercasesKeywordsAndBreaksClauses() {
        let out = formatter.format("select id, name from users where id = 1")
        XCTAssertEqual(
            out,
            """
            SELECT
              id,
              name
            FROM users
            WHERE id = 1

            """
        )
    }

    func testPreservesStringsAndComments() {
        let out = formatter.format("select 'From' from t -- keep me")
        XCTAssertTrue(out.contains("'From'"))
        XCTAssertTrue(out.contains("-- keep me"))
        XCTAssertTrue(out.contains("SELECT"))
        XCTAssertTrue(out.contains("FROM t"))
    }

    func testJoinsStayTogether() {
        let out = formatter.format("select * from a left join b on a.id = b.id")
        XCTAssertTrue(out.contains("LEFT JOIN b"), out)
        XCTAssertTrue(out.contains("ON a.id = b.id"), out)
    }

    func testAndBreaksInWhere() {
        let out = formatter.format("select * from t where a = 1 and b = 2")
        XCTAssertTrue(out.contains("WHERE a = 1"))
        XCTAssertTrue(out.contains("\n  AND b = 2"))
    }

    func testCastOperatorNotSplit() {
        let out = formatter.format("select f.id::text from t")
        XCTAssertTrue(out.contains("f.id::text"))
    }

    func testStatementsSeparated() {
        let out = formatter.format("select 1; select 2;")
        XCTAssertTrue(out.contains("SELECT 1;"), out)
        XCTAssertTrue(out.contains("SELECT 2;"), out)
        XCTAssertTrue(out.contains("\n\n"), out)
    }

    func testEmpty() {
        XCTAssertEqual(formatter.format("   "), "")
    }

    func testRedisFormatIsNoOp() {
        let sql = "set foo bar\nget foo"
        XCTAssertEqual(formatter.format(sql, dialect: .redis), sql)
    }
}
