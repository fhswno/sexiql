import XCTest
@testable import SQLGrid
import SQLDrivers

final class ResultSetModelTests: XCTestCase {
    private func makeModel() -> ResultSetModel {
        ResultSetModel(columns: [
            GridColumn(ordinal: 0, name: "id", dataType: "int4"),
            GridColumn(ordinal: 1, name: "name", dataType: "text"),
        ])
    }

    func testAppendAndComplete() {
        var model = makeModel()
        XCTAssertFalse(model.isComplete)
        model.append(SQLRow(values: [.int(1), .string("a")]))
        model.append(SQLRow(values: [.int(2), .string("b")]))
        model.finish(totalRowCount: 2)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.totalRowCount, 2)
        XCTAssertEqual(model[0, 1], .string("a"))
        XCTAssertEqual(model[5, 5], .null)
    }

    func testRowsIgnoredAfterCompletion() {
        var model = makeModel()
        model.finish(totalRowCount: 0)
        model.append(SQLRow(values: [.int(1), .string("a")]))
        XCTAssertEqual(model.rows.count, 0)
    }

    func testMismatchedRowWidthIgnored() {
        var model = makeModel()
        model.append(SQLRow(values: [.int(1)]))
        XCTAssertEqual(model.rows.count, 0)
    }

    func testDisplayRowsFilterAndSort() {
        var model = makeModel()
        model.append(SQLRow(values: [.int(2), .string("bob")]))
        model.append(SQLRow(values: [.int(1), .string("alice")]))
        model.append(SQLRow(values: [.int(3), .string("carol")]))
        model.finish()

        let filtered = ResultDisplayRows.build(
            model: model,
            filterText: "a",
            sortOrdinal: 0,
            sortAscending: true
        )
        XCTAssertEqual(filtered.map(\.id), [1, 2])
        XCTAssertEqual(filtered.map { $0.values[1] }, [.string("alice"), .string("carol")])

        let snap = ResultDisplayRows.snapshot(
            model: model,
            filterText: "",
            sortOrdinal: 1,
            sortAscending: false
        )
        XCTAssertEqual(snap.columns, ["id", "name"])
        XCTAssertEqual(snap.rows.map { $0[1] }, [.string("carol"), .string("bob"), .string("alice")])
    }
}
