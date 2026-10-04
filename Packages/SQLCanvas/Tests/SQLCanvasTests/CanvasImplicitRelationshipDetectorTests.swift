import XCTest
@testable import SQLCanvas

final class CanvasImplicitRelationshipDetectorTests: XCTestCase {
    private func table(_ name: String, columns: [CanvasColumn]) -> CanvasTable {
        CanvasTable(id: "public.\(name)", name: name, schema: "public", columns: columns, position: CanvasPoint(x: 0, y: 0))
    }

    private func pk(_ name: String) -> CanvasColumn {
        CanvasColumn(name: name, dataType: "bigint", isPrimaryKey: true, isNullable: false)
    }

    func testDetectsSingularPluralReference() {
        let customers = table("customers", columns: [pk("id")])
        let orders = table("orders", columns: [
            pk("id"),
            CanvasColumn(name: "customer_id", dataType: "bigint"),
        ])
        let candidates = CanvasImplicitRelationshipDetector.findCandidates(
            tables: [customers, orders],
            existingEdges: []
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].fromTableID, orders.id)
        XCTAssertEqual(candidates[0].fromColumn, "customer_id")
        XCTAssertEqual(candidates[0].toTableID, customers.id)
        XCTAssertEqual(candidates[0].toColumn, "id")
    }

    func testIESPluralMatching() {
        let category = table("category", columns: [pk("id")])
        let items = table("items", columns: [
            pk("id"),
            CanvasColumn(name: "category_ref", dataType: "bigint"),
        ])
        let candidates = CanvasImplicitRelationshipDetector.findCandidates(
            tables: [category, items],
            existingEdges: []
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].toTableID, category.id)
    }

    func testSkipsDeclaredEdges() {
        let customers = table("customers", columns: [pk("id")])
        let orders = table("orders", columns: [
            pk("id"),
            CanvasColumn(name: "customer_id", dataType: "bigint", isForeignKey: true),
        ])
        let declared = [CanvasEdge(
            fromTableID: orders.id,
            fromColumn: "customer_id",
            toTableID: customers.id,
            toColumn: "id"
        )]
        let candidates = CanvasImplicitRelationshipDetector.findCandidates(
            tables: [customers, orders],
            existingEdges: declared
        )
        XCTAssertTrue(candidates.isEmpty, "declared FK columns are skipped by the isForeignKey filter")
    }

    func testSkipsTypeIncompatible() {
        let users = table("users", columns: [pk("id"), CanvasColumn(name: "name", dataType: "text")])
        let orders = table("orders", columns: [
            pk("id"),
            CanvasColumn(name: "user_name_id", dataType: "text"),
        ])
        let candidates = CanvasImplicitRelationshipDetector.findCandidates(
            tables: [users, orders],
            existingEdges: []
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func testSelfReferenceAllowed() {
        let employee = table("employee", columns: [
            pk("id"),
            CanvasColumn(name: "employee_id", dataType: "bigint"),
        ])
        let candidates = CanvasImplicitRelationshipDetector.findCandidates(
            tables: [employee],
            existingEdges: []
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].toTableID, employee.id)
        XCTAssertEqual(candidates[0].toColumn, "id")

        let categories = table("categories", columns: [
            pk("id"),
            CanvasColumn(name: "parent_id", dataType: "bigint"),
        ])
        XCTAssertTrue(
            CanvasImplicitRelationshipDetector.findCandidates(tables: [categories], existingEdges: []).isEmpty,
            "parent_id encodes no table name — the naming heuristic cannot propose it"
        )
    }
}
