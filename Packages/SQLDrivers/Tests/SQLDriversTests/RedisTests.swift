import XCTest
@testable import SQLDrivers
import SQLCore

final class RedisTests: XCTestCase {
    func testTokenizeQuotesAndEscapes() {
        XCTAssertEqual(RedisCommand.tokenize("SET foo bar"), ["SET", "foo", "bar"])
        XCTAssertEqual(RedisCommand.tokenize("SET foo \"hello world\""), ["SET", "foo", "hello world"])
        XCTAssertEqual(RedisCommand.tokenize("SET foo 'hello world'"), ["SET", "foo", "hello world"])
        XCTAssertEqual(RedisCommand.tokenize("SET foo \"say \\\"hi\\\"\""), ["SET", "foo", "say \"hi\""])
    }

    func testSplitStatementsSkipsComments() {
        let lines = RedisCommand.splitStatements("SET a 1\n# comment\nGET a\n\n")
        XCTAssertEqual(lines, ["SET a 1", "GET a"])
    }

    func testRESPRoundTripStatusAndBulk() throws {
        var decoder = RedisDecoder(data: Data("+PONG\r\n".utf8))
        XCTAssertEqual(try decoder.consumeReply(), .status("PONG"))

        decoder = RedisDecoder(data: RedisCommand.encode(["SET", "k", "v"]))
        guard case .array(let items) = try decoder.readReply(), let items else {
            return XCTFail("expected array")
        }
        XCTAssertEqual(items.map(\.string), ["SET", "k", "v"])
    }

    func testRESPNullBulkAndArray() throws {
        var decoder = RedisDecoder(data: Data("$-1\r\n".utf8))
        XCTAssertEqual(try decoder.consumeReply(), .bulk(nil))
        decoder = RedisDecoder(data: Data("*-1\r\n".utf8))
        XCTAssertEqual(try decoder.consumeReply(), .array(nil))
    }

    func testRESPIntegerAndError() throws {
        var decoder = RedisDecoder(data: Data(":42\r\n".utf8))
        XCTAssertEqual(try decoder.consumeReply(), .integer(42))
        decoder = RedisDecoder(data: Data("-ERR unknown command\r\n".utf8))
        XCTAssertEqual(try decoder.consumeReply(), .error("ERR unknown command"))
    }

    func testResultGridHGETALLAndLRANGE() throws {
        let hash = try RedisResultGrid.queryResult(
            for: .array([.bulk(Data("name".utf8)), .bulk(Data("ada".utf8))]),
            command: ["HGETALL", "user"]
        )
        XCTAssertEqual(hash.columns?.map(\.name), ["field", "value"])
        XCTAssertEqual(hash.rows.first?.values, [.string("name"), .string("ada")])

        let list = try RedisResultGrid.queryResult(
            for: .array([.bulk(Data("a".utf8)), .bulk(Data("b".utf8))]),
            command: ["LRANGE", "q", "0", "-1"]
        )
        XCTAssertEqual(list.columns?.map(\.name), ["index", "value"])
        XCTAssertEqual(list.rows[1].values, [.int(1), .string("b")])
    }

    func testWriteCommandsReturnAffectedCount() throws {
        let set = try RedisResultGrid.queryResult(for: .status("OK"), command: ["SET", "k", "v"])
        XCTAssertEqual(set.affectedRowCount, 1)
        XCTAssertNil(set.columns)
    }

    func testEditCommands() {
        let hash = RedisEdit.table(forCommand: ["HGETALL", "user:1"], columns: [
            SQLColumn(name: "field", dataType: "bulk", ordinal: 0),
            SQLColumn(name: "value", dataType: "bulk", ordinal: 1),
        ])
        XCTAssertEqual(hash?.name, "user:1")
        XCTAssertTrue(RedisEdit.isRedisTable(hash!))
        XCTAssertEqual(
            RedisEdit.updateCommand(table: hash!, column: 1, newValue: .string("ada"), primaryKeyValues: [.string("name")]),
            "HSET user:1 name ada"
        )
        XCTAssertEqual(
            RedisEdit.deleteCommand(table: hash!, primaryKeyValues: [.string("name")]),
            "HDEL user:1 name"
        )
    }

    func testScanStopHelper() {
        XCTAssertTrue(RedisConnection.scanShouldStop(keyCount: 10, cap: 2000, cursor: "0"))
        XCTAssertTrue(RedisConnection.scanShouldStop(keyCount: 2000, cap: 2000, cursor: "5"))
        XCTAssertFalse(RedisConnection.scanShouldStop(keyCount: 10, cap: 2000, cursor: "5"))
        XCTAssertEqual(RedisConnection.defaultScanCap, 2000)
    }

    func testKeyLoadCommands() {
        XCTAssertEqual(RedisResultGrid.keyLoadCommand(type: "hash", key: "user:1"), "HGETALL user:1")
        XCTAssertEqual(RedisResultGrid.keyLoadCommand(type: "list", key: "q"), "LRANGE q 0 -1")
        XCTAssertTrue(RedisResultGrid.keyLoadCommand(type: "string", key: "has space").contains("\""))
    }

    func testLiveConnectAndCommands() async throws {
        guard let urlString = ProcessInfo.processInfo.environment["SEXIQL_TEST_REDIS_URL"],
              let url = URL(string: urlString),
              let host = url.host else {
            return
        }
        let profile = ConnectionProfile(
            name: "redis-integration",
            kind: .redis,
            host: host,
            port: url.port ?? 6379,
            database: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            username: url.user ?? "",
            tlsMode: url.scheme == "rediss" ? .required : .off
        )
        let connection = RedisConnection(profile: profile)
        try await connection.connect(password: url.password)
        let version = try await connection.serverVersion()
        XCTAssertNotNil(version)
        _ = try await connection.execute("SET sexiql:test 1")
        let get = try await connection.execute("GET sexiql:test")
        XCTAssertEqual(get.rows.first?.values.first, .string("1"))
        _ = try await connection.execute("DEL sexiql:test")
        try await connection.disconnect()
    }
}
