import XCTest
@testable import SQLCanvas

final class CanvasHierarchicalLayoutTests: XCTestCase {
    private func table(_ name: String, columns: [CanvasColumn]) -> CanvasTable {
        CanvasTable(id: "public.\(name)", name: name, schema: "public", columns: columns, position: CanvasPoint(x: 0, y: 0))
    }

    private func pkColumn(_ name: String) -> CanvasColumn {
        CanvasColumn(name: name, dataType: "bigint", isPrimaryKey: true, isNullable: false)
    }

    func testRanksFollowRelationshipFlow() {
        let users = table("users", columns: [pkColumn("id"), CanvasColumn(name: "email", dataType: "text")])
        let teams = table("teams", columns: [pkColumn("id"), CanvasColumn(name: "name", dataType: "text")])
        let memberships = table("memberships", columns: [
            CanvasColumn(name: "user_id", dataType: "bigint", isForeignKey: true),
            CanvasColumn(name: "team_id", dataType: "bigint", isForeignKey: true),
        ])

        let edges = [
            CanvasEdge(fromTableID: memberships.id, fromColumn: "user_id", toTableID: users.id, toColumn: "id"),
            CanvasEdge(fromTableID: memberships.id, fromColumn: "team_id", toTableID: teams.id, toColumn: "id"),
        ]

        let arranged = CanvasHierarchicalLayout.arrange(tables: [memberships, users, teams], edges: edges)

        let positions = Dictionary(uniqueKeysWithValues: arranged.map { ($0.id, $0.position) })
        let usersX = positions[users.id]!.x
        let teamsX = positions[teams.id]!.x
        let membershipsX = positions[memberships.id]!.x

        XCTAssertTrue(usersX < membershipsX, "users should rank left of memberships")
        XCTAssertTrue(teamsX < membershipsX, "teams should rank left of memberships")
    }

    func testLayoutIsDeterministic() {
        let a = table("alpha", columns: [pkColumn("id")])
        let b = table("beta", columns: [pkColumn("id"), CanvasColumn(name: "alpha_id", dataType: "bigint", isForeignKey: true)])
        let c = table("gamma", columns: [pkColumn("id"), CanvasColumn(name: "beta_id", dataType: "bigint", isForeignKey: true)])
        let edges = [
            CanvasEdge(fromTableID: b.id, fromColumn: "alpha_id", toTableID: a.id, toColumn: "id"),
            CanvasEdge(fromTableID: c.id, fromColumn: "beta_id", toTableID: b.id, toColumn: "id"),
        ]
        let shuffled = [c, a, b]

        let first = CanvasHierarchicalLayout.arrange(tables: [a, b, c], edges: edges)
        let second = CanvasHierarchicalLayout.arrange(tables: shuffled, edges: edges)
        XCTAssertEqual(first.count, second.count)
        for (f, s) in zip(first, second) {
            XCTAssertEqual(f.id, s.id)
            XCTAssertEqual(f.position, s.position)
        }
    }

    func testRelaxationPreservesMinimumGaps() {
        var tables = [
            table("root_a", columns: [pkColumn("id"), CanvasColumn(name: "x", dataType: "text"), CanvasColumn(name: "y", dataType: "text")]),
            table("root_b", columns: [pkColumn("id")]),
        ]
        let childA = table("child_a", columns: [CanvasColumn(name: "root_a_id", dataType: "bigint", isForeignKey: true)])
        let childB = table("child_b", columns: [CanvasColumn(name: "root_b_id", dataType: "bigint", isForeignKey: true)])
        tables.append(contentsOf: [childA, childB])

        let edges = [
            CanvasEdge(fromTableID: childA.id, fromColumn: "root_a_id", toTableID: "public.root_a", toColumn: "id"),
            CanvasEdge(fromTableID: childB.id, fromColumn: "root_b_id", toTableID: "public.root_b", toColumn: "id"),
        ]

        let arranged = CanvasHierarchicalLayout.arrange(tables: tables, edges: edges)

        let byX = Dictionary(grouping: arranged) { $0.position.x }
        for (_, group) in byX {
            let sorted = group.sorted { $0.position.y < $1.position.y }
            for i in 1..<sorted.count {
                let previous = sorted[i - 1]
                let current = sorted[i]
                let previousHeight = CanvasCardMetrics.tableHeight(columnCount: previous.columns.count)
                XCTAssertTrue(
                    current.position.y >= previous.position.y + previousHeight + 55.99,
                    "\(current.name) overlaps \(previous.name)"
                )
            }
        }
    }

    func testSelfReferencingEdgeDoesNotBreakRanking() {
        let node = table("tree", columns: [pkColumn("id"), CanvasColumn(name: "parent_id", dataType: "bigint", isForeignKey: true)])
        let leaf = table("leaf", columns: [CanvasColumn(name: "tree_id", dataType: "bigint", isForeignKey: true)])
        let edges = [
            CanvasEdge(fromTableID: node.id, fromColumn: "parent_id", toTableID: node.id, toColumn: "id"),
            CanvasEdge(fromTableID: leaf.id, fromColumn: "tree_id", toTableID: node.id, toColumn: "id"),
        ]
        let arranged = CanvasHierarchicalLayout.arrange(tables: [node, leaf], edges: edges)
        let positions = Dictionary(uniqueKeysWithValues: arranged.map { ($0.id, $0.position) })
        XCTAssertTrue(positions[node.id]!.x < positions[leaf.id]!.x)
    }

    func testSingleParentChildAlignsTowardItsParent() {
        let rootA = table("root_a", columns: [pkColumn("id"), CanvasColumn(name: "x", dataType: "text"), CanvasColumn(name: "y", dataType: "text")])
        let rootB = table("root_b", columns: [pkColumn("id")])
        let childA = table("child_a", columns: [CanvasColumn(name: "root_a_id", dataType: "bigint", isForeignKey: true)])
        let childB = table("child_b", columns: [CanvasColumn(name: "root_b_id", dataType: "bigint", isForeignKey: true)])

        let edges = [
            CanvasEdge(fromTableID: childA.id, fromColumn: "root_a_id", toTableID: rootA.id, toColumn: "id"),
            CanvasEdge(fromTableID: childB.id, fromColumn: "root_b_id", toTableID: rootB.id, toColumn: "id"),
        ]
        let arranged = CanvasHierarchicalLayout.arrange(tables: [rootA, rootB, childA, childB], edges: edges)
        let positions = Dictionary(uniqueKeysWithValues: arranged.map { ($0.id, $0.position) })

        func centerY(_ id: String) -> Double {
            let table = arranged.first { $0.id == id }!
            return positions[id]!.y + CanvasCardMetrics.tableHeight(columnCount: table.columns.count) / 2
        }

        let rootACenter = centerY(rootA.id)
        let rootBCenter = centerY(rootB.id)
        let childACenter = centerY(childA.id)
        let childBCenter = centerY(childB.id)

        XCTAssertTrue(
            abs(childACenter - rootACenter) < abs(childACenter - rootBCenter),
            "child_a should align toward root_a"
        )
        XCTAssertTrue(
            abs(childBCenter - rootBCenter) < abs(childBCenter - rootACenter),
            "child_b should align toward root_b"
        )
    }

    func testEdgeGeometrySelfLoopAnchorsOnLeftSide() throws {
        let node = table("tree", columns: [pkColumn("id"), CanvasColumn(name: "parent_id", dataType: "bigint", isForeignKey: true)])
        let edge = CanvasEdge(fromTableID: node.id, fromColumn: "parent_id", toTableID: node.id, toColumn: "id")
        guard let anchors = CanvasEdgeGeometry.anchors(for: edge, tables: [node.id: node]) else {
            return XCTFail("self-loop anchors unresolved")
        }
        XCTAssertEqual(anchors.start.x, node.position.x)
        XCTAssertEqual(anchors.end.x, node.position.x)
    }
}

private func XCTUnwrapAlternative<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "test", code: 1) }
    return value
}

final class CanvasEdgeGeometryNotationTests: XCTestCase {
    func testCrowFootProngsPointAwayFromTail() {
        let prongs = CanvasEdgeGeometry.crowFootProngs(at: CGPoint(x: 100, y: 100), toward: CGPoint(x: 0, y: 100))
        let box = prongs.boundingRect
        XCTAssertTrue(box.maxX > 100, "prongs extend toward the edge continuation")
    }

    func testOneTickPerpendicularToEndOfEdge() {
        let tick = CanvasEdgeGeometry.oneTick(at: CGPoint(x: 100, y: 100), toward: CGPoint(x: 100, y: 0))
        let box = tick.boundingRect
        XCTAssertTrue(box.width > 8, "tick spans horizontally")
        XCTAssertTrue(box.height < 1, "tick has no vertical extent for a vertical edge")
    }
}
