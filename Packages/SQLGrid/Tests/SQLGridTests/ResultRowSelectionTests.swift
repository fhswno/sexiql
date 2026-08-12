import XCTest
@testable import SQLGrid
import SQLDrivers

final class ResultRowSelectionTests: XCTestCase {
    private let display = [10, 20, 30, 40, 50]

    func testPlainClickReplacesSelection() {
        let current = ResultRowSelection(selectedIDs: [10, 20], anchorID: 20)
        let next = ResultRowSelection.click(
            id: 40,
            command: false,
            shift: false,
            current: current,
            displayIDs: display
        )
        XCTAssertEqual(next.selectedIDs, [40])
        XCTAssertEqual(next.anchorID, 40)
    }

    func testShiftClickSelectsDisplayRangeAndKeepsAnchor() {
        let current = ResultRowSelection(selectedIDs: [20], anchorID: 20)
        let next = ResultRowSelection.click(
            id: 50,
            command: false,
            shift: true,
            current: current,
            displayIDs: display
        )
        XCTAssertEqual(next.selectedIDs, [20, 30, 40, 50])
        XCTAssertEqual(next.anchorID, 20)
    }

    func testShiftClickWithoutAnchorSelectsSingle() {
        let next = ResultRowSelection.click(
            id: 30,
            command: false,
            shift: true,
            current: ResultRowSelection(),
            displayIDs: display
        )
        XCTAssertEqual(next.selectedIDs, [30])
        XCTAssertEqual(next.anchorID, 30)
    }

    func testCommandClickToggles() {
        let current = ResultRowSelection(selectedIDs: [10, 30], anchorID: 10)
        let removed = ResultRowSelection.click(
            id: 30,
            command: true,
            shift: false,
            current: current,
            displayIDs: display
        )
        XCTAssertEqual(removed.selectedIDs, [10])
        XCTAssertEqual(removed.anchorID, 30)

        let added = ResultRowSelection.click(
            id: 50,
            command: true,
            shift: false,
            current: removed,
            displayIDs: display
        )
        XCTAssertEqual(added.selectedIDs, [10, 50])
        XCTAssertEqual(added.anchorID, 50)
    }

    func testGutterDragSelectsContiguousRange() {
        let next = ResultRowSelection.gutterDrag(from: 50, to: 20, displayIDs: display)
        XCTAssertEqual(next.selectedIDs, [20, 30, 40, 50])
        XCTAssertEqual(next.anchorID, 50)
    }

    func testIndicesIntersectingMarquee() {
        let range = ResultRowSelection.indicesIntersecting(
            minY: 30,
            maxY: 90,
            rowHeight: 28,
            rowCount: 10
        )
        XCTAssertEqual(range, 1..<4)
        XCTAssertNil(
            ResultRowSelection.indicesIntersecting(
                minY: 0,
                maxY: 10,
                rowHeight: 28,
                rowCount: 0
            )
        )
    }

    func testDragEndIndexClamps() {
        XCTAssertEqual(
            ResultRowSelection.dragEndIndex(
                startDisplayIndex: 2,
                translationHeight: 56,
                rowHeight: 28,
                rowCount: 5
            ),
            4
        )
        XCTAssertEqual(
            ResultRowSelection.dragEndIndex(
                startDisplayIndex: 1,
                translationHeight: -200,
                rowHeight: 28,
                rowCount: 5
            ),
            0
        )
        XCTAssertEqual(
            ResultRowSelection.dragEndIndex(
                startDisplayIndex: 0,
                translationHeight: 10,
                rowHeight: 28,
                rowCount: 5
            ),
            0
        )
    }

    func testPruneDropsHiddenIDs() {
        let current = ResultRowSelection(selectedIDs: [10, 20, 99], anchorID: 99)
        let next = ResultRowSelection.prune(current, visibleIDs: [10, 20, 30])
        XCTAssertEqual(next.selectedIDs, [10, 20])
        XCTAssertNil(next.anchorID)
    }

    func testPrepareContextSelectionKeepsExisting() {
        let current = ResultRowSelection(selectedIDs: [10, 20], anchorID: 10)
        let kept = ResultRowSelection.prepareContextSelection(id: 20, current: current)
        XCTAssertEqual(kept, current)
        let replaced = ResultRowSelection.prepareContextSelection(id: 40, current: current)
        XCTAssertEqual(replaced.selectedIDs, [40])
        XCTAssertEqual(replaced.anchorID, 40)
    }

    func testSelectedPreservesDisplayOrder() {
        let rows = [
            ResultDisplayRow(id: 2, values: [.int(2)]),
            ResultDisplayRow(id: 0, values: [.int(0)]),
            ResultDisplayRow(id: 1, values: [.int(1)]),
        ]
        let selected = ResultDisplayRows.selected(from: rows, ids: [1, 2])
        XCTAssertEqual(selected.map(\.id), [2, 1])
    }

    func testTSVIncludesHeaderAndNULL() {
        let text = ResultDisplayRows.tsv(
            columns: ["id", "name"],
            rows: [[.int(1), .null], [.int(2), .string("a\tb")]]
        )
        XCTAssertEqual(text, "id\tname\n1\tNULL\n2\ta\tb")
    }

    func testValuesSQLSingleAndMulti() {
        XCTAssertEqual(
            ResultDisplayRows.valuesSQL(rows: [[.int(1), .string("a'b")]]),
            "VALUES (1, 'a''b');"
        )
        let multi = ResultDisplayRows.valuesSQL(rows: [
            [.int(1), .null],
            [.int(2), .string("x")],
        ])
        XCTAssertEqual(multi, "VALUES\n(1, NULL),\n(2, 'x');")
    }
}
