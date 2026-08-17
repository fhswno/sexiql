import XCTest
@testable import SQLCore

final class AIMentionTests: XCTestCase {
    func testParsesBareAndQualifiedMentions() {
        let tokens = AIMention.tokens(in: "join @clients to @public.companies")
        XCTAssertEqual(tokens.map(\.raw), ["clients", "public.companies"])
        XCTAssertEqual(tokens[0].schema, nil)
        XCTAssertEqual(tokens[0].name, "clients")
        XCTAssertEqual(tokens[1].schema, "public")
        XCTAssertEqual(tokens[1].name, "companies")
    }

    func testIgnoresEmailAddresses() {
        let tokens = AIMention.tokens(in: "email dave@host.com then @clients")
        XCTAssertEqual(tokens.map(\.raw), ["clients"])
    }

    func testTokenAtCaretForPartialMention() {
        let text = "use @cli"
        let token = AIMention.tokenAtCaret(in: text, utf16Offset: text.utf16.count)
        XCTAssertEqual(token?.name, "cli")
        XCTAssertEqual(token?.utf16Range.lowerBound, 4)
    }

    func testTokenAtBareAtSign() {
        let text = "see @"
        let token = AIMention.tokenAtCaret(in: text, utf16Offset: text.utf16.count)
        XCTAssertEqual(token?.name, "")
        XCTAssertEqual(token?.filterPrefix, "")
    }

    func testTokenAtQualifiedPrefix() {
        let text = "@public.cli"
        let token = AIMention.tokenAtCaret(in: text, utf16Offset: text.utf16.count)
        XCTAssertEqual(token?.schema, "public")
        XCTAssertEqual(token?.name, "cli")
        XCTAssertEqual(token?.filterPrefix, "public.cli")
    }

    func testNoTokenWhenCaretIsNotInMention() {
        XCTAssertNil(AIMention.tokenAtCaret(in: "select 1", utf16Offset: 3))
        XCTAssertNil(AIMention.tokenAtCaret(in: "a@b", utf16Offset: 3))
    }

    func testFormatsColumns() {
        let text = AIMention.formatTables([
            AIMentionTable(
                displayName: "public.companies",
                columns: [
                    AIMentionColumn(name: "id", dataType: "uuid", isPrimaryKey: true, isNullable: false),
                    AIMentionColumn(name: "name", dataType: "text", isPrimaryKey: false, isNullable: false),
                    AIMentionColumn(name: "note", dataType: "text", isPrimaryKey: false, isNullable: true),
                ]
            ),
        ])
        XCTAssertTrue(text.contains("- public.companies"))
        XCTAssertTrue(text.contains("  id uuid PK NOT NULL"))
        XCTAssertTrue(text.contains("  name text NOT NULL"))
        XCTAssertTrue(text.contains("  note text NULL"))
    }

    func testMatchRankPrefersPrefixThenContains() {
        XCTAssertEqual(AIMention.matchRank(query: "s3", name: "s3_iam_connections", qualified: "app.s3_iam_connections", schema: "app"), 1)
        XCTAssertEqual(AIMention.matchRank(query: "iam", name: "s3_iam_connections", qualified: "app.s3_iam_connections", schema: "app"), 3)
        XCTAssertEqual(AIMention.matchRank(query: "s3ic", name: "s3_iam_connections", qualified: "app.s3_iam_connections", schema: "app"), 4)
        XCTAssertNil(AIMention.matchRank(query: "zzz", name: "s3_iam_connections", qualified: "app.s3_iam_connections", schema: "app"))
    }

    func testFormatsMissingColumns() {
        let text = AIMention.formatTables([
            AIMentionTable(displayName: "clients", columns: []),
        ])
        XCTAssertTrue(text.contains("- clients"))
        XCTAssertTrue(text.contains("(columns not loaded)"))
    }
}
