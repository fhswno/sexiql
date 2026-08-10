import XCTest
@testable import SQLExplainer

final class ExplainNodeTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let node = ExplainNode(
            nodeType: "Hash Join",
            relation: nil,
            totalCost: 42.5,
            actualRows: 100,
            children: [
                ExplainNode(nodeType: "Seq Scan", relation: "users"),
                ExplainNode(nodeType: "Seq Scan", relation: "orders"),
            ]
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ExplainNode.self, from: data)
        XCTAssertEqual(decoded, node)
        XCTAssertEqual(decoded.children.count, 2)
    }
}
