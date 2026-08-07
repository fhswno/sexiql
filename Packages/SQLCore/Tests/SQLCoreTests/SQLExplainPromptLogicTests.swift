import XCTest
@testable import SQLCore

enum SQLExplainPromptLogic {
    static func userMessage(sql: String, dialectName: String?, schemaTables: [String]) -> String {
        var parts: [String] = []
        parts.append("Dialect: \(dialectName ?? "unknown")")
        if schemaTables.isEmpty {
            parts.append("Schema tables: (none loaded)")
        } else {
            let limited = schemaTables.prefix(80)
            var schema = "Schema tables (\(schemaTables.count)):\n"
            for name in limited { schema += "- \(name)\n" }
            parts.append(schema.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        parts.append("SQL:\n```sql\n\(sql.trimmingCharacters(in: .whitespacesAndNewlines))\n```")
        parts.append("Explain what this SQL does.")
        return parts.joined(separator: "\n\n")
    }
}

final class SQLExplainPromptLogicTests: XCTestCase {
    func testIncludesSQLAndDialect() {
        let msg = SQLExplainPromptLogic.userMessage(
            sql: "SELECT 1;",
            dialectName: "SQLite",
            schemaTables: ["users", "orders"]
        )
        XCTAssertTrue(msg.contains("Dialect: SQLite"))
        XCTAssertTrue(msg.contains("SELECT 1;"))
        XCTAssertTrue(msg.contains("- users"))
        XCTAssertTrue(msg.contains("- orders"))
    }

    func testEmptySchema() {
        let msg = SQLExplainPromptLogic.userMessage(sql: "SELECT 1", dialectName: nil, schemaTables: [])
        XCTAssertTrue(msg.contains("none loaded"))
        XCTAssertTrue(msg.contains("unknown"))
    }
}
