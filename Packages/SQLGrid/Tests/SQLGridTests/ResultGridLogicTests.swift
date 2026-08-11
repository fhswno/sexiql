import XCTest
@testable import SQLGrid
import SQLDrivers

final class ResultGridLogicTests: XCTestCase {
    private func model() -> ResultSetModel {
        var m = ResultSetModel(columns: [
            GridColumn(ordinal: 0, name: "id", dataType: "int"),
            GridColumn(ordinal: 1, name: "name", dataType: "text"),
        ])
        m.append(SQLRow(values: [.int(2), .string("bob")]))
        m.append(SQLRow(values: [.int(1), .string("alice")]))
        m.append(SQLRow(values: [.int(3), .string("carol")]))
        m.finish()
        return m
    }

    func testFilterAndSort() {
        let m = model()
        let indices = ResultGridLogic.visibleIndices(
            model: m,
            filterText: "a",
            sortColumn: 0,
            sortAscending: true
        )
        XCTAssertEqual(indices, [1, 2])
    }

    func testParsedValue() {
        XCTAssertEqual(ResultGridLogic.parsedValue("NULL"), .null)
        XCTAssertEqual(ResultGridLogic.parsedValue("42"), .int(42))
        XCTAssertEqual(ResultGridLogic.parsedValue("true"), .bool(true))
        XCTAssertEqual(ResultGridLogic.parsedValue("hi"), .string("hi"))
    }

    func testValuesSQL() {
        let sql = ResultGridLogic.valuesSQL(fields: [.int(1), .string("a'b"), .null])
        XCTAssertEqual(sql, "VALUES (1, 'a''b', NULL);")
    }

    func testTSVField() {
        XCTAssertEqual(ResultGridLogic.tsvField(.null), "NULL")
        XCTAssertEqual(ResultGridLogic.tsvField(.string("x")), "x")
    }
}
