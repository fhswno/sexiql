import XCTest
@testable import SQLCanvas

final class CanvasNarrationParserTests: XCTestCase {
    private let tableIDs: Set<String> = ["public.users", "public.orders", "public.products"]
    private let edgeIDs: Set<String> = ["public.orders.customer_id->public.users.id"]

    private func makeParser() -> CanvasNarrationParser {
        CanvasNarrationParser(knownTableIDs: tableIDs, knownEdgeIDs: edgeIDs)
    }

    func testIngestsValidNDJSONAcrossChunks() {
        var parser = makeParser()
        let line1 = #"{"kind":"overview","title":"Overview","text":"A shop schema.","tables":["public.users"],"edges":[]}"# + "\n"
        let partial = #"{"kind":"cluster","title":"Orders","text":"Orders reference users.","tables":["public.orders","public.users"],"edges":["# + "\n"
        let rest = #""public.orders.customer_id->public.users.id"]}"# + "\n"

        var segments = parser.ingest(line1)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .overview)
        XCTAssertEqual(segments[0].tableIDs, ["public.users"])

        segments = parser.ingest(partial)
        XCTAssertTrue(segments.isEmpty, "incomplete JSON line must not emit")

        segments = parser.ingest(rest)
        segments += parser.finish()
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .cluster)
        XCTAssertEqual(segments[0].edgeIDs, edgeIDs.sorted())
    }

    func testUnknownTableReferencesStripped() {
        var parser = makeParser()
        let line = #"{"kind":"detail","title":"X","text":"Claims a ghost table.","tables":["public.ghost","public.users"],"edges":["nope->nope"]}"# + "\n"
        let segments = parser.ingest(line)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].tableIDs, ["public.users"])
        XCTAssertTrue(segments[0].edgeIDs.isEmpty)
    }

    func testProseLinesBecomePlainSegments() {
        var parser = makeParser()
        var segments = parser.ingest("This model ignored the JSON instruction.\n")
        segments += parser.finish()
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .detail)
        XCTAssertTrue(segments[0].text.contains("ignored"))
    }

    func testFinishFlushesPartialLine() {
        var parser = makeParser()
        var segments = parser.ingest("no trailing newline here")
        XCTAssertTrue(segments.isEmpty)
        segments = parser.finish()
        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].text.contains("no trailing newline"))
    }

    func testUnknownKindMapsToDetail() {
        var parser = makeParser()
        let line = #"{"kind":"poetry","title":"Ode","text":"Tables in the wind."}"# + "\n"
        let segments = parser.ingest(line)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .detail)
    }

    func testSegIDsAreSequentialAndUnique() {
        var parser = makeParser()
        let lines = #"{"kind":"overview","title":"a","text":"a"}"# + "\n" +
            #"{"kind":"detail","title":"b","text":"b"}"# + "\n" +
            #"{"kind":"closing","title":"c","text":"c"}"# + "\n"
        let segments = parser.ingest(lines)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(Set(segments.map(\.id)).count, 3)
    }
}

final class CanvasNarrationParserHardeningTests: XCTestCase {
    private let tableIDs: Set<String> = ["public.users", "public.orders"]

    func testMarkdownFencesStripped() {
        var parser = CanvasNarrationParser(knownTableIDs: tableIDs, knownEdgeIDs: [])
        let lines = "```json\n" +
            #"{"kind":"overview","title":"Overview","text":"A shop schema.","tables":["public.users"]}"# + "\n" +
            "```\n"
        let segments = parser.ingest(lines) + parser.finish()
        XCTAssertEqual(segments.count, 1, "fence lines are dropped, not emitted as steps")
        XCTAssertEqual(segments[0].kind, .overview)
    }

    func testSegmentCountCappedAtEight() {
        var parser = CanvasNarrationParser(knownTableIDs: tableIDs, knownEdgeIDs: [])
        var lines = ""
        for i in 1...12 {
            lines += #"{"kind":"detail","title":"S\#(i)","text":"Step \#(i)."}"# + "\n"
        }
        let segments = parser.ingest(lines)
        XCTAssertEqual(segments.count, 8, "extras beyond 8 are discarded")
    }

    func testConsecutiveDuplicateTextCollapses() {
        var parser = CanvasNarrationParser(knownTableIDs: tableIDs, knownEdgeIDs: [])
        let line = #"{"kind":"detail","title":"Same","text":"Exactly the same sentence."}"# + "\n"
        let segments = parser.ingest(line + line)
        XCTAssertEqual(segments.count, 1, "back-to-back duplicates collapse to one step")
    }
}
