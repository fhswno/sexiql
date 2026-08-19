import XCTest
@testable import SQLEditor

final class SQLPayloadGuardTests: XCTestCase {
    func testAcceptsSelectAndWith() {
        XCTAssertTrue(SQLPayloadGuard.looksLikeSQL("SELECT 1"))
        XCTAssertTrue(SQLPayloadGuard.looksLikeSQL("  -- note\nWITH c AS (SELECT 1) SELECT * FROM c"))
        XCTAssertTrue(SQLPayloadGuard.looksLikeSQL("(SELECT 1)"))
        XCTAssertTrue(SQLPayloadGuard.looksLikeSQL("EXPLAIN SELECT 1"))
        XCTAssertTrue(SQLPayloadGuard.looksLikeSQL("COPY t FROM STDIN"))
    }

    func testRejectsErrorPreamble() {
        let sql = """
        relation "public.salesforce_connections" does not exist [42P01]

        SELECT portal_tenant_id FROM public.salesforce_connections
        """
        XCTAssertFalse(SQLPayloadGuard.looksLikeSQL(sql))
        XCTAssertFalse(SQLPayloadGuard.looksLikeSQL("syntax error at or near \"index\""))
        XCTAssertFalse(SQLPayloadGuard.looksLikeSQL(""))
    }
}
