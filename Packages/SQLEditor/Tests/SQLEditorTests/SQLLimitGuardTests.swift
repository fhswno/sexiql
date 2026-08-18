import XCTest
@testable import SQLEditor

final class SQLLimitGuardTests: XCTestCase {
    private let guardLimit = SQLLimitGuard()

    func testAppendsToBareSelect() {
        let out = guardLimit.apply("SELECT * FROM t")
        XCTAssertTrue(out.didLimit)
        XCTAssertEqual(out.sql, "SELECT * FROM t LIMIT 1000")
    }

    func testInsertsBeforeSemicolon() {
        let out = guardLimit.apply("SELECT * FROM t;")
        XCTAssertTrue(out.didLimit)
        XCTAssertEqual(out.sql, "SELECT * FROM t LIMIT 1000;")
    }

    func testLeavesExistingLimit() {
        let sql = "SELECT * FROM t LIMIT 10"
        let out = guardLimit.apply(sql)
        XCTAssertFalse(out.didLimit)
        XCTAssertEqual(out.sql, sql)
    }

    func testIgnoresLimitInsideSubquery() {
        let out = guardLimit.apply("SELECT * FROM (SELECT * FROM t LIMIT 10) x")
        XCTAssertTrue(out.didLimit)
        XCTAssertTrue(out.sql.hasSuffix(" LIMIT 1000"))
    }

    func testWithCTE() {
        let out = guardLimit.apply("WITH c AS (SELECT 1) SELECT * FROM c")
        XCTAssertTrue(out.didLimit)
        XCTAssertTrue(out.sql.contains(" LIMIT 1000"))
    }

    func testSkipsDMLAndExplain() {
        XCTAssertFalse(guardLimit.apply("INSERT INTO t VALUES (1)").didLimit)
        XCTAssertFalse(guardLimit.apply("UPDATE t SET a = 1").didLimit)
        XCTAssertFalse(guardLimit.apply("EXPLAIN SELECT * FROM t").didLimit)
        XCTAssertFalse(guardLimit.apply("CREATE TABLE t (id int)").didLimit)
    }

    func testFetchCountsAsLimited() {
        let sql = "SELECT * FROM t FETCH FIRST 20 ROWS ONLY"
        let out = guardLimit.apply(sql)
        XCTAssertFalse(out.didLimit)
        XCTAssertEqual(out.sql, sql)
    }

    func testNilOrNonPositiveLimitIsNoOp() {
        let sql = "SELECT * FROM t"
        XCTAssertFalse(guardLimit.apply(sql, limit: nil).didLimit)
        XCTAssertEqual(guardLimit.apply(sql, limit: nil).sql, sql)
        XCTAssertFalse(guardLimit.apply(sql, limit: 0).didLimit)
        XCTAssertEqual(guardLimit.apply(sql, limit: 0).sql, sql)
        XCTAssertFalse(guardLimit.apply(sql, limit: -1).didLimit)
    }

    func testCustomLimit() {
        let out = guardLimit.apply("SELECT * FROM t", limit: 100)
        XCTAssertTrue(out.didLimit)
        XCTAssertEqual(out.sql, "SELECT * FROM t LIMIT 100")
    }

    func testExistingLimitWithJSONOperatorUnchanged() {
        let sql = """
        SELECT id FROM q_events
        WHERE event = 'Nightly Sync > Client'
          AND input->>'client' = 'ironclad'
        ORDER BY created_at DESC
        LIMIT 10
        """
        let out = guardLimit.apply(sql)
        XCTAssertFalse(out.didLimit)
        XCTAssertEqual(out.sql, sql)
    }
}
