import XCTest
@testable import SQLCanvas

final class CanvasGraphSummaryTests: XCTestCase {
    private func table(_ name: String, columns: [CanvasColumn]) -> CanvasTable {
        CanvasTable(id: "public.\(name)", name: name, schema: "public", columns: columns, position: CanvasPoint(x: 0, y: 0))
    }

    private func pk(_ name: String) -> CanvasColumn {
        CanvasColumn(name: name, dataType: "bigint", isPrimaryKey: true, isNullable: false)
    }

    func testContainsTablesAndRelationships() {
        let users = table("users", columns: [pk("id"), CanvasColumn(name: "email", dataType: "text")])
        let orders = table("orders", columns: [
            pk("id"),
            CanvasColumn(name: "customer_id", dataType: "bigint", isForeignKey: true),
        ])
        let edges = [CanvasEdge(fromTableID: orders.id, fromColumn: "customer_id", toTableID: users.id, toColumn: "id")]

        let summary = CanvasGraphSummary.build(tables: [users, orders], edges: edges)

        XCTAssertTrue(summary.contains("TABLES:"))
        XCTAssertTrue(summary.contains("- users:"))
        XCTAssertTrue(summary.contains("[PK]"))
        XCTAssertTrue(summary.contains("RELATIONSHIPS"))
        XCTAssertTrue(summary.contains("orders.customer_id -> users.id (N:1)"))
    }

    func testStableOrderingRegardlessOfInputOrder() {
        let a = table("alpha", columns: [pk("id")])
        let b = table("beta", columns: [pk("id")])
        let first = CanvasGraphSummary.build(tables: [b, a], edges: [])
        let second = CanvasGraphSummary.build(tables: [a, b], edges: [])
        XCTAssertEqual(first, second)
        let alphaIndex = first.range(of: "- alpha:")!.lowerBound
        let betaIndex = first.range(of: "- beta:")!.lowerBound
        XCTAssertTrue(alphaIndex < betaIndex)
    }

    func testVirtualEdgeMarked() {
        let a = table("a", columns: [pk("id")])
        let b = table("b", columns: [pkColumn("id")])
        let edges = [CanvasEdge(
            fromTableID: a.id, fromColumn: "id",
            toTableID: b.id, toColumn: "id",
            isVirtual: true
        )]
        let summary = CanvasGraphSummary.build(tables: [a, b], edges: edges)
        XCTAssertTrue(summary.contains("[virtual"))
    }

    private func pkColumn(_ name: String) -> CanvasColumn {
        CanvasColumn(name: name, dataType: "bigint", isPrimaryKey: true, isNullable: false)
    }

    func testLargeSchemaTriggersTruncation() {
        var tables: [CanvasTable] = []
        for index in 0..<300 {
            var columns = [pk("id")]
            for c in 0..<30 {
                columns.append(CanvasColumn(name: "col_\(index)_\(c)", dataType: "text"))
            }
            tables.append(table("t\(String(format: "%03d", index))", columns: columns))
        }
        let summary = CanvasGraphSummary.build(tables: tables, edges: [], characterBudget: 12_000)
        XCTAssertTrue(summary.count <= 12_000 + 200, "graceful truncation note allowed")
        XCTAssertTrue(summary.contains("truncated") || summary.contains("+"))
    }
}
