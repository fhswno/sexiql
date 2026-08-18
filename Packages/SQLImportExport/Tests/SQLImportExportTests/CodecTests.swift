import XCTest
@testable import SQLImportExport
import SQLDrivers

final class CSVCodecTests: XCTestCase {
    func testEncodeHeadersAndRows() {
        let csv = CSVCodec.encode(
            columns: ["id", "name"],
            rows: [
                [.int(1), .string("ada")],
                [.int(2), .null],
            ]
        )
        XCTAssertEqual(csv, "id,name\r\n1,ada\r\n2,\r\n")
    }

    func testEncodeQuotesSpecialCharacters() {
        let csv = CSVCodec.encode(
            columns: ["a"],
            rows: [[.string("he said \"hi\", ok")]]
        )
        XCTAssertEqual(csv, "a\r\n\"he said \"\"hi\"\", ok\"\r\n")
    }

    func testRoundTrip() throws {
        let original = "id,name,note\r\n1,ada,\"line1\nline2\"\r\n2,bob,\"a,b,c\"\r\n3,carol,\"\"\"quoted\"\"\"\r\n"
        let rows = try CSVCodec.parse(original)
        XCTAssertEqual(rows.count, 4) // includes header
        XCTAssertEqual(rows[0], ["id", "name", "note"])
        XCTAssertEqual(rows[1], ["1", "ada", "line1\nline2"])
        XCTAssertEqual(rows[2], ["2", "bob", "a,b,c"])
        XCTAssertEqual(rows[3], ["3", "carol", "\"quoted\""])
    }

    func testLFLineEndings() throws {
        let rows = try CSVCodec.parse("a,b\n1,2\n3,4\n")
        XCTAssertEqual(rows, [["a", "b"], ["1", "2"], ["3", "4"]])
    }

    func testTrailingNewlineOptional() throws {
        let rows = try CSVCodec.parse("a,b\n1,2")
        XCTAssertEqual(rows, [["a", "b"], ["1", "2"]])
    }

    func testUnterminatedQuoteThrows() {
        XCTAssertThrowsError(try CSVCodec.parse("a,b\n\"unterminated"))
    }

    func testEmptyFields() throws {
        let rows = try CSVCodec.parse("a,,c\n,,\n")
        XCTAssertEqual(rows[1], ["", "", ""])
    }

    func testSemicolonDelimiter() throws {
        let rows = try CSVCodec.parse(
            "id;name\n1;\"a;b\"\n",
            dialect: CSVDialect(delimiter: ";", quote: "\"")
        )
        XCTAssertEqual(rows, [["id", "name"], ["1", "a;b"]])
    }

    func testTabDelimiter() throws {
        let rows = try CSVCodec.parse(
            "id\tname\n1\tada\n",
            dialect: .tsv
        )
        XCTAssertEqual(rows, [["id", "name"], ["1", "ada"]])
    }

    func testSniffPrefersSemicolon() {
        let dialect = CSVCodec.sniff(Data("id;name;city\n1;ada;paris\n".utf8))
        XCTAssertEqual(dialect.delimiter, ";")
    }

    func testSniffPrefersTab() {
        let dialect = CSVCodec.sniff(Data("id\tname\n1\tada\n".utf8))
        XCTAssertEqual(dialect.delimiter, "\t")
    }

    func testSniffKeepsComma() {
        let dialect = CSVCodec.sniff(Data("id,name\n1,ada\n".utf8))
        XCTAssertEqual(dialect.delimiter, ",")
    }
}

final class JSONCodecTests: XCTestCase {
    func testEncodeTypedValues() throws {
        let json = try JSONCodec.encode(
            columns: ["id", "name", "active", "score"],
            rows: [[.int(1), .string("ada"), .bool(true), .double(9.5)]]
        )
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(parsed[0]["id"] as? Int64, 1)
        XCTAssertEqual(parsed[0]["name"] as? String, "ada")
        XCTAssertEqual(parsed[0]["active"] as? Bool, true)
        XCTAssertEqual(parsed[0]["score"] as? Double, 9.5)
    }

    func testParseObjects() throws {
        let json = """
        [{"id": 1, "name": "ada"}, {"id": 2, "name": "bob", "extra": "x"}]
        """
        let result = try JSONCodec.parse(Data(json.utf8))
        XCTAssertEqual(result.columns, ["extra", "id", "name"])
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0], [.null, .int(1), .string("ada")])
        XCTAssertEqual(result.rows[1], [.string("x"), .int(2), .string("bob")])
    }

    func testParseNullAndTypes() throws {
        let json = """
        [{"a": null, "b": "7", "c": 3.5}]
        """
        let result = try JSONCodec.parse(Data(json.utf8))
        XCTAssertEqual(result.rows[0], [.null, .int(7), .double(3.5)])
    }
    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try JSONCodec.parse(Data("[not json".utf8)))
        XCTAssertThrowsError(try JSONCodec.parse(Data("{\"not\": \"an array\"}".utf8)))
    }

    func testInferredValue() {
        XCTAssertEqual(JSONCodec.inferredValue("42"), .int(42))
        XCTAssertEqual(JSONCodec.inferredValue("-3.25"), .double(-3.25))
        XCTAssertEqual(JSONCodec.inferredValue("NULL"), .null)
        XCTAssertEqual(JSONCodec.inferredValue("hello"), .string("hello"))
        XCTAssertEqual(JSONCodec.inferredValue(""), .string(""))
    }
}
