import XCTest
@testable import SQLCore

final class StatementWriteGuardTests: XCTestCase {
    func testAllowsReads() {
        XCTAssertFalse(StatementWriteGuard.isWrite("SELECT 1", kind: .postgres))
        XCTAssertFalse(StatementWriteGuard.isWrite("  -- note\nSELECT * FROM t", kind: .mysql))
        XCTAssertFalse(StatementWriteGuard.isWrite("EXPLAIN SELECT 1", kind: .sqlite))
        XCTAssertFalse(StatementWriteGuard.isWrite("GET foo", kind: .redis))
        XCTAssertFalse(StatementWriteGuard.isWrite("SCAN 0", kind: .redis))
        XCTAssertFalse(StatementWriteGuard.isWrite("HGETALL user:1", kind: .redis))
    }

    func testBlocksSQLWrites() {
        XCTAssertTrue(StatementWriteGuard.isWrite("DELETE FROM t", kind: .postgres))
        XCTAssertTrue(StatementWriteGuard.isWrite("INSERT INTO t VALUES (1)", kind: .mysql))
        XCTAssertTrue(StatementWriteGuard.isWrite("UPDATE t SET a = 1", kind: .sqlite))
        XCTAssertTrue(StatementWriteGuard.isWrite("CREATE TABLE t (id int)", kind: .postgres))
        XCTAssertTrue(StatementWriteGuard.isWrite("WITH x AS (SELECT 1) DELETE FROM t", kind: .postgres))
    }

    func testBlocksRedisWrites() {
        XCTAssertTrue(StatementWriteGuard.isWrite("SET foo bar", kind: .redis))
        XCTAssertTrue(StatementWriteGuard.isWrite("DEL foo", kind: .redis))
        XCTAssertTrue(StatementWriteGuard.isWrite("HSET user:1 name ada", kind: .redis))
        XCTAssertFalse(StatementWriteGuard.isWrite("# comment\nGET foo", kind: .redis))
    }
}
