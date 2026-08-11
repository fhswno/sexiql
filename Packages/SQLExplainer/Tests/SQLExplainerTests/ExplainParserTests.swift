import Foundation
import XCTest
@testable import SQLExplainer

final class ExplainParserTests: XCTestCase {
    func testPostgresJSONBuildsTreeAndMapsFields() throws {
        let fixture = Data(
            """
            [
              {
                "Plan": {
                  "Node Type": "Hash Join",
                  "Join Type": "Inner",
                  "Startup Cost": 1.25,
                  "Total Cost": 83.5,
                  "Plan Rows": 12,
                  "Plan Width": 64,
                  "Actual Startup Time": 0.031,
                  "Actual Total Time": 0.412,
                  "Actual Rows": 12,
                  "Parallel Aware": false,
                  "Plans": [
                    {
                      "Node Type": "Seq Scan",
                      "Relation Name": "users",
                      "Plan Rows": 100,
                      "Filter": "(active = true)"
                    },
                    {
                      "Node Type": "Index Scan",
                      "Relation Name": "orders",
                      "Index Name": "orders_user_id_idx",
                      "Actual Rows": 12,
                      "Output": ["id", "user_id"]
                    }
                  ]
                },
                "Planning Time": 0.102,
                "Execution Time": 0.451
              }
            ]
            """.utf8
        )

        guard let node = try ExplainParser().parse(jsonData: fixture) else {
            XCTFail("expected a plan node")
            return
        }
        XCTAssertEqual(node.nodeType, "Hash Join")
        XCTAssertNil(node.relation)
        XCTAssertEqual(node.startupCost, 1.25)
        XCTAssertEqual(node.totalCost, 83.5)
        XCTAssertEqual(node.planRows, 12)
        XCTAssertEqual(node.planWidth, 64)
        XCTAssertEqual(node.actualStartupTime, 0.031)
        XCTAssertEqual(node.actualTotalTime, 0.412)
        XCTAssertEqual(node.actualRows, 12)
        XCTAssertEqual(node.detail["Join Type"], "Inner")
        XCTAssertEqual(node.detail["Parallel Aware"], "false")
        XCTAssertEqual(node.children.count, 2)
        XCTAssertEqual(node.children[0].nodeType, "Seq Scan")
        XCTAssertEqual(node.children[0].relation, "users")
        XCTAssertEqual(node.children[0].detail["Filter"], "(active = true)")
        XCTAssertEqual(node.children[1].nodeType, "Index Scan")
        XCTAssertEqual(node.children[1].relation, "orders")
        XCTAssertEqual(node.children[1].detail["Index Name"], "orders_user_id_idx")
        XCTAssertEqual(node.children[1].detail["Output"], "[\"id\",\"user_id\"]")
    }

    func testPostgresJSONAllowsPlanningOnlyPlans() throws {
        let fixture = Data(
            """
            [{
              "Plan": {
                "Node Type": "Seq Scan",
                "Relation Name": "accounts",
                "Startup Cost": 0,
                "Total Cost": 18.4,
                "Plan Rows": 4,
                "Plan Width": 32
              }
            }]
            """.utf8
        )

        guard let node = try ExplainParser().parse(jsonData: fixture) else {
            XCTFail("expected a plan node")
            return
        }
        XCTAssertEqual(node.nodeType, "Seq Scan")
        XCTAssertEqual(node.relation, "accounts")
        XCTAssertNil(node.actualStartupTime)
        XCTAssertNil(node.actualTotalTime)
        XCTAssertNil(node.actualRows)
        XCTAssertTrue(node.children.isEmpty)
    }

    func testPostgresEmptyArrayReturnsNil() throws {
        XCTAssertNil(try ExplainParser().parse(jsonData: Data("[]".utf8)))
    }

    func testMySQLJSONBuildsQueryBlockAndTable() throws {
        let fixture = Data(
            """
            {
              "query_block": {
                "select_id": 1,
                "cost_info": {"query_cost": "3.50"},
                "table": {
                  "table_name": "users",
                  "access_type": "ALL",
                  "rows_examined_per_scan": 12,
                  "filtered": "100.00"
                }
              }
            }
            """.utf8
        )
        guard let node = try ExplainParser().parse(mysqlJSONData: fixture) else {
            XCTFail("expected a MySQL plan")
            return
        }
        XCTAssertEqual(node.nodeType, "Query Block")
        XCTAssertEqual(node.children.count, 1)
        XCTAssertEqual(node.children[0].nodeType, "ALL")
        XCTAssertEqual(node.children[0].relation, "users")
        XCTAssertEqual(node.children[0].planRows, 12)
    }

    func testPostgresErrorsAreSpecific() {
        do {
            _ = try ExplainParser().parse(jsonData: Data("not json".utf8))
            XCTFail("expected malformed JSON")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .malformedJSON)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try ExplainParser().parse(jsonData: Data("{}".utf8))
            XCTFail("expected invalid root")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .invalidJSONStructure)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try ExplainParser().parse(jsonData: Data("[{\"Planning Time\": 1}]".utf8))
            XCTFail("expected missing Plan")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .missingPlan)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try ExplainParser().parse(jsonData: Data("[{\"Plan\": {}}]".utf8))
            XCTFail("expected missing Node Type")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .missingNodeType)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try ExplainParser().parse(jsonData: Data("[{\"Plan\": {\"Node Type\": \"Seq Scan\", \"Plan Rows\": true}}]".utf8))
            XCTFail("expected invalid numeric value")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .invalidNodeValue(key: "Plan Rows"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSQLiteTextBuildsHierarchyAndPreservesDetail() throws {
        let fixture = [
            "QUERY PLAN",
            "|--SCAN users",
            "|  \u{0060}--SEARCH orders USING COVERING INDEX orders_user_id (user_id=?)",
            "\u{0060}--USE TEMP B-TREE FOR ORDER BY",
        ].joined(separator: "\n")

        guard let root = try ExplainParser().parse(sqliteText: fixture) else {
            XCTFail("expected a plan root")
            return
        }
        XCTAssertEqual(root.nodeType, "QUERY PLAN")
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[0].nodeType, "SCAN")
        XCTAssertEqual(root.children[0].relation, "users")
        XCTAssertEqual(root.children[0].detail["Detail"], "SCAN users")
        XCTAssertEqual(root.children[0].children.count, 1)
        XCTAssertEqual(root.children[0].children[0].nodeType, "SEARCH")
        XCTAssertEqual(root.children[0].children[0].relation, "orders")
        XCTAssertEqual(root.children[1].nodeType, "USE TEMP B-TREE")
        XCTAssertNil(root.children[1].relation)
    }

    func testSQLiteRowsBuildHierarchyFromRawColumns() throws {
        let rows = [
            ["id", "parent", "notused", "detail"],
            ["2", "0", "0", "SCAN users"],
            ["5", "2", "0", "SEARCH orders USING INDEX orders_user_id (user_id=?)"],
        ]

        guard let root = try ExplainParser().parse(sqliteRows: rows) else {
            XCTFail("expected a plan root")
            return
        }
        XCTAssertEqual(root.nodeType, "SCAN")
        XCTAssertEqual(root.relation, "users")
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.children[0].nodeType, "SEARCH")
        XCTAssertEqual(root.children[0].relation, "orders")

        let typedRows = [
            SQLiteExplainRow(id: 10, parent: 0, detail: "SCAN products", notUsed: 0),
            SQLiteExplainRow(id: 11, parentID: 10, detail: "USE TEMP B-TREE FOR ORDER BY"),
        ]
        guard let typedRoot = try ExplainParser().parse(sqliteRows: typedRows) else {
            XCTFail("expected a typed plan root")
            return
        }
        XCTAssertEqual(typedRoot.nodeType, "SCAN")
        XCTAssertEqual(typedRoot.children[0].nodeType, "USE TEMP B-TREE")
    }

    func testSQLiteEmptyTextReturnsNil() throws {
        XCTAssertNil(try ExplainParser().parse(sqliteText: "\nQUERY PLAN\n\n"))
        XCTAssertNil(try ExplainParser().parse(sqliteRows: [] as [[String]]))
    }

    func testSQLiteErrorsAreSpecific() {
        do {
            _ = try ExplainParser().parse(sqliteRows: [["bad", "0", "0", "SCAN users"]])
            XCTFail("expected invalid row")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .invalidSQLiteRow(index: 0, message: "id and parent must be integers"))
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try ExplainParser().parse(sqliteRows: [
                SQLiteExplainRow(id: 2, parentID: 0, detail: "SCAN users"),
                SQLiteExplainRow(id: 3, parentID: 99, detail: "SCAN orders"),
            ])
            XCTFail("expected missing parent")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .invalidSQLiteTree(message: "node 3 refers to missing parent 99"))
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try ExplainParser().parse(sqliteRows: [
                SQLiteExplainRow(id: 2, parentID: 3, detail: "SCAN users"),
                SQLiteExplainRow(id: 3, parentID: 2, detail: "SCAN orders"),
            ])
            XCTFail("expected cycle")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .invalidSQLiteTree(message: "plan contains no root node"))
        } catch {
            XCTFail("unexpected error \(error)")
        }

        do {
            _ = try ExplainParser().parse(sqliteText: "|--SCAN users\n|  |  \u{0060}--SEARCH orders")
            XCTFail("expected invalid indentation")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .invalidSQLiteText(line: 2, message: "plan indentation skips a level"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
