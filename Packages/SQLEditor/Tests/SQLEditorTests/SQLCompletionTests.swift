import XCTest
@testable import SQLEditor

final class SQLCompletionTests: XCTestCase {
    private let engine = SQLCompletionEngine()

    private func catalog() -> SQLCompletionCatalog {
        SQLCompletionCatalog(
            objects: [
                SQLCompletionObject(
                    name: "accounts",
                    insertText: "accounts",
                    kind: .table,
                    columns: [
                        SQLCompletionColumn(name: "id", insertText: "id", detail: "int", tableName: "accounts"),
                        SQLCompletionColumn(name: "kernel_id", insertText: "kernel_id", detail: "text", tableName: "accounts"),
                    ]
                ),
                SQLCompletionObject(
                    name: "users",
                    insertText: "users",
                    kind: .table,
                    columns: [
                        SQLCompletionColumn(name: "email", insertText: "email", detail: "text", tableName: "users"),
                    ]
                ),
            ]
        )
    }

    func testDoesNotCompleteInsideString() {
        let sql = "SELECT 'se"
        let result = engine.suggestions(sql: sql, cursor: sql.utf16.count, catalog: catalog(), force: false)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testDoesNotAutoCompleteShortPrefix() {
        let sql = "S"
        let result = engine.suggestions(sql: sql, cursor: 1, catalog: catalog(), force: false)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testKeywordPrefix() {
        let sql = "SE"
        let result = engine.suggestions(sql: sql, cursor: 2, catalog: catalog(), force: false)
        XCTAssertEqual(result.items.first?.label, "SELECT")
        XCTAssertEqual(result.replaceRange, NSRange(location: 0, length: 2))
    }

    func testWherePrefersColumnsOverKeywords() {
        let sql = "SELECT FROM companies WHERE fo"
        let companies = SQLCompletionObject(
            name: "companies",
            insertText: "companies",
            kind: .table,
            columns: [
                SQLCompletionColumn(name: "founded_year", insertText: "founded_year", tableName: "companies"),
                SQLCompletionColumn(name: "company_name", insertText: "company_name", tableName: "companies"),
            ]
        )
        let result = engine.suggestions(
            sql: sql,
            cursor: sql.utf16.count,
            catalog: SQLCompletionCatalog(objects: [companies]),
            force: false
        )
        XCTAssertEqual(result.items.first?.label, "founded_year")
        XCTAssertEqual(result.items.first?.kind, .column)
    }

    func testSchemaQualifiedTableAfterDot() {
        let clients = SQLCompletionObject(
            name: "clients",
            insertText: "momentum.clients",
            kind: .table,
            schema: "momentum"
        )
        let sql = "SELECT * FROM momentum.cli"
        let result = engine.suggestions(
            sql: sql,
            cursor: sql.utf16.count,
            catalog: SQLCompletionCatalog(objects: [clients]),
            force: false
        )
        XCTAssertEqual(result.items.first?.label, "momentum.clients")
        XCTAssertEqual(result.items.first?.insertText, "clients")
    }

    func testUnqualifiedPrefixSuggestsQualifiedTable() {
        let clients = SQLCompletionObject(
            name: "clients",
            insertText: "momentum.clients",
            kind: .table,
            schema: "momentum"
        )
        let sql = "SELECT * FROM mom"
        let result = engine.suggestions(
            sql: sql,
            cursor: sql.utf16.count,
            catalog: SQLCompletionCatalog(objects: [clients]),
            force: false
        )
        XCTAssertEqual(result.items.first?.insertText, "momentum.clients")
    }

    func testFromPrefersTables() {
        let sql = "SELECT * FROM acc"
        let result = engine.suggestions(sql: sql, cursor: sql.utf16.count, catalog: catalog(), force: false)
        XCTAssertEqual(result.items.first?.label, "accounts")
        XCTAssertEqual(result.items.first?.kind, .table)
    }

    func testDotShowsColumns() {
        let sql = "SELECT a.ker FROM accounts a"
        let cursor = (sql as NSString).range(of: "ker").location + 3
        let result = engine.suggestions(sql: sql, cursor: cursor, catalog: catalog(), force: false)
        XCTAssertEqual(result.items.first?.label, "kernel_id")
        XCTAssertEqual(result.items.first?.kind, .column)
    }

    func testEmptyPrefixAfterDot() {
        let sql = "SELECT a."
        let result = engine.suggestions(sql: sql, cursor: sql.utf16.count, catalog: catalog(), force: false)
        XCTAssertTrue(result.items.contains { $0.label == "id" })
        XCTAssertTrue(result.items.contains { $0.label == "kernel_id" })
    }

    func testForceCompletesEmptyPrefix() {
        let result = engine.suggestions(sql: "", cursor: 0, catalog: catalog(), force: true)
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertTrue(result.items.contains { $0.label == "SELECT" })
    }

    func testInsertColumnListUsesTableColumns() {
        let sql = """
        CREATE TABLE companies (id INTEGER, company_name TEXT, industry TEXT, founded_year INTEGER);
        INSERT INTO companies (fou
        """
        let catalog = SQLCompletionCatalog(objects: SQLCompletionEngine.objectsDeclared(in: sql))
        let result = engine.suggestions(sql: sql, cursor: sql.utf16.count, catalog: catalog, force: false)
        XCTAssertEqual(result.items.first?.label, "founded_year")
    }

    func testParsesCreateTableColumns() {
        let sql = """
        CREATE TABLE companies (
            id INTEGER PRIMARY KEY,
            company_name TEXT NOT NULL,
            industry TEXT,
            founded_year INTEGER
        );
        """
        let objects = SQLCompletionEngine.objectsDeclared(in: sql)
        XCTAssertEqual(objects.first?.name, "companies")
        XCTAssertEqual(objects.first?.columns.map(\.name), ["id", "company_name", "industry", "founded_year"])
    }

    func testNeedsQuoting() {
        XCTAssertTrue(SQLCompletionEngine.needsQuoting("SELECT"))
        XCTAssertTrue(SQLCompletionEngine.needsQuoting("weird-name"))
        XCTAssertFalse(SQLCompletionEngine.needsQuoting("accounts"))
        XCTAssertFalse(SQLCompletionEngine.needsQuoting("kernel_id"))
    }
}
