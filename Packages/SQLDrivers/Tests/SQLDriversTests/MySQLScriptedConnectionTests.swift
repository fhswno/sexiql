import XCTest
import Synchronization
@testable import SQLDrivers
import SQLCore

final class ScriptedMySQLTransport: MySQLTransporting, @unchecked Sendable {
    private final class State {
        var pending: [MySQLPacket] = []
        var writes: [Data] = []
        var closed = false
    }

    private let state = Mutex(State())

    init(packets: [MySQLPacket]) {
        state.withLock { $0.pending = packets }
    }

    func enqueue(_ packet: MySQLPacket) {
        state.withLock { $0.pending.append(packet) }
    }

    func recordedWrites() -> [Data] {
        state.withLock { $0.writes }
    }

    func isClosed() -> Bool {
        state.withLock { $0.closed }
    }

    func connect(host: String, port: Int) async throws {}

    func startTLS(serverName: String?, verifyCertificate: Bool) async throws {}

    func write(_ data: Data) async throws {
        state.withLock { $0.writes.append(data) }
    }

    func readPacket(expectedSequence: UInt8) async throws -> MySQLPacket {
        try state.withLock { state in
            guard !state.pending.isEmpty else { throw MySQLWireError.truncated("script exhausted") }
            return state.pending.removeFirst()
        }
    }

    func close() async {
        state.withLock { $0.closed = true }
    }
}

final class MySQLScriptedConnectionTests: XCTestCase {
    // MARK: - Packet Fixtures

    private let moreResults: UInt16 = 0x0008

    private func packet(_ payload: Data, _ sequence: UInt8) -> MySQLPacket {
        MySQLPacket(sequence: sequence, payload: payload)
    }

    private func handshakePacket(deprecateEOF: Bool) -> Data {
        var payload = Data([0x0a])
        payload.append(MySQLWire.cstring("8.0.36"))
        payload.append(MySQLWire.uint32(1))
        payload.append(Data("12345678".utf8))
        payload.append(0)
        payload.append(MySQLWire.uint16(0xA200))
        payload.append(33)
        payload.append(MySQLWire.uint16(2))
        payload.append(MySQLWire.uint16(deprecateEOF ? 0x0118 : 0x0018))
        payload.append(21)
        payload.append(contentsOf: repeatElement(UInt8(0), count: 10))
        payload.append(Data("123456789012".utf8))
        payload.append(0)
        payload.append(MySQLWire.cstring("mysql_native_password"))
        return payload
    }

    private func okPacket(affected: UInt64 = 0, lastID: UInt64 = 0, status: UInt16 = 0) -> Data {
        var payload = Data([0x00])
        payload.append(MySQLWire.lengthEncodedInteger(affected))
        payload.append(MySQLWire.lengthEncodedInteger(lastID))
        payload.append(MySQLWire.uint16(status))
        return payload
    }

    private func eofPacket(status: UInt16 = 0) -> Data {
        Data([0xfe, 0x00, 0x00, UInt8(status & 0xff), UInt8(status >> 8)])
    }

    private func feHeaderOKTerminator(status: UInt16 = 0) -> Data {
        eofPacket(status: status)
    }

    private func errorPacket(code: UInt16 = 1044) -> Data {
        var payload = Data([0xff])
        payload.append(MySQLWire.uint16(code))
        payload.append(Data("#42000".utf8))
        payload.append(Data("rejected".utf8))
        return payload
    }

    private func columnCount(_ count: Int) -> Data {
        MySQLWire.lengthEncodedInteger(UInt64(count))
    }

    private func columnDefinition(name: String, type: UInt8) -> Data {
        var payload = Data()
        payload.append(MySQLWire.lengthEncoded("def"))
        payload.append(MySQLWire.lengthEncoded("app"))
        payload.append(MySQLWire.lengthEncoded("u"))
        payload.append(MySQLWire.lengthEncoded("users"))
        payload.append(MySQLWire.lengthEncoded(name))
        payload.append(MySQLWire.lengthEncoded(name))
        payload.append(0x0c)
        payload.append(contentsOf: [0x21, 0x00])
        payload.append(contentsOf: [0, 0, 0, 0])
        payload.append(type)
        payload.append(contentsOf: [0, 0])
        payload.append(0)
        payload.append(contentsOf: [0, 0])
        return payload
    }

    private func textRow(_ values: [String]) -> Data {
        var payload = Data()
        for value in values {
            payload.append(MySQLWire.lengthEncoded(Data(value.utf8)))
        }
        return payload
    }

    private func binaryRow(_ values: [Int64]) -> Data {
        var payload = Data([0x00])
        let bitmapLength = (values.count + 7 + 2) / 8
        payload.append(contentsOf: repeatElement(UInt8(0), count: bitmapLength))
        for value in values {
            payload.append(MySQLWire.uint32(UInt32(truncatingIfNeeded: value)))
        }
        return payload
    }

    private func prepareOK(statementID: UInt32, columns: UInt16, parameters: UInt16) -> Data {
        var payload = Data([0x00])
        payload.append(MySQLWire.uint32(statementID))
        payload.append(MySQLWire.uint16(columns))
        payload.append(MySQLWire.uint16(parameters))
        payload.append(0)
        payload.append(MySQLWire.uint16(0))
        return payload
    }

    // MARK: - Harness

    private func makeConnection(
        deprecateEOF: Bool,
        packets: [MySQLPacket],
        readOnly: Bool = false
    ) -> (MySQLConnection, ScriptedMySQLTransport) {
        let profile = ConnectionProfile(
            name: "scripted",
            kind: .mysql,
            host: "h",
            port: 3306,
            username: "u",
            tlsMode: .off,
            readOnly: readOnly
        )
        let transport = ScriptedMySQLTransport(packets: packets)
        let connection = MySQLConnection(profile: profile, transport: transport)
        return (connection, transport)
    }

    // MARK: - Text Protocol

    func testLegacyEOFSelectReturnsAllRowsInOrder() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: false, packets: [])
        let handshake = packet(handshakePacket(deprecateEOF: false), 0)
        let authOK = packet(okPacket(), 2)
        for packet in [handshake, authOK] { transport.enqueue(packet) }
        try await connection.connect(password: nil)

        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "name", type: MySQLColumnType.varString), 2))
        transport.enqueue(packet(eofPacket(status: 2), 3))
        transport.enqueue(packet(textRow(["a"]), 4))
        transport.enqueue(packet(textRow(["b"]), 5))
        transport.enqueue(packet(eofPacket(status: 2), 6))

        let result = try await connection.execute("SELECT name FROM t")
        XCTAssertEqual(result.columns?.map(\.name), ["name"])
        XCTAssertEqual(result.rows.map { $0.values }, [[.string("a")], [.string("b")]])
        XCTAssertEqual(transport.recordedWrites().count, 2, "handshake response + COM_QUERY")
    }

    func testDeprecateEOFSelectReturnsAllRowsInOrder() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "name", type: MySQLColumnType.varString), 2))
        transport.enqueue(packet(textRow(["first"]), 3))
        transport.enqueue(packet(textRow(["second"]), 4))
        transport.enqueue(packet(feHeaderOKTerminator(status: 2), 5))

        let result = try await connection.execute("SELECT name FROM t")
        XCTAssertEqual(result.rows.map { $0.values }, [[.string("first")], [.string("second")]])
    }

    func testDeprecateEOFEmptyResultSet() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "n", type: MySQLColumnType.varString), 2))
        transport.enqueue(packet(feHeaderOKTerminator(status: 0), 3))

        let result = try await connection.execute("SELECT n FROM t")
        XCTAssertEqual(result.rows.count, 0)
        XCTAssertTrue(result.rows.isEmpty)
    }

    func testLegacyEmptyResultSet() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: false, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: false), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "n", type: MySQLColumnType.varString), 2))
        transport.enqueue(packet(eofPacket(status: 0), 3))
        transport.enqueue(packet(eofPacket(status: 0), 4))

        let result = try await connection.execute("SELECT n FROM t")
        XCTAssertTrue(result.rows.isEmpty)
    }

    func testAffectedRowsPath() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(okPacket(affected: 3, status: 0), 1))

        let result = try await connection.execute("UPDATE t SET a = 1")
        XCTAssertEqual(result.affectedRowCount, 3)
    }

    // MARK: - Prepared Statements

    func testDeprecateEOFPreparedSelectWithParameters() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(prepareOK(statementID: 7, columns: 1, parameters: 1), 1))
        transport.enqueue(packet(columnDefinition(name: "id", type: MySQLColumnType.long), 2))
        transport.enqueue(packet(columnDefinition(name: "id", type: MySQLColumnType.long), 3))
        transport.enqueue(packet(columnCount(1), 4))
        transport.enqueue(packet(columnDefinition(name: "id", type: MySQLColumnType.long), 5))
        transport.enqueue(packet(binaryRow([42]), 6))
        transport.enqueue(packet(feHeaderOKTerminator(status: 0), 7))

        let result = try await connection.execute("SELECT id FROM t WHERE id = ?", parameters: [.int(42)])
        XCTAssertEqual(result.rows.map { $0.values }, [[.int(42)]])
    }

    func testLegacyPreparedSelectWithParameters() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: false, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: false), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(prepareOK(statementID: 7, columns: 1, parameters: 1), 1))
        transport.enqueue(packet(columnDefinition(name: "id", type: MySQLColumnType.long), 2))
        transport.enqueue(packet(eofPacket(status: 0), 3))
        transport.enqueue(packet(columnDefinition(name: "id", type: MySQLColumnType.long), 4))
        transport.enqueue(packet(eofPacket(status: 0), 5))
        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "id", type: MySQLColumnType.long), 2))
        transport.enqueue(packet(eofPacket(status: 0), 3))
        transport.enqueue(packet(binaryRow([9]), 4))
        transport.enqueue(packet(eofPacket(status: 0), 5))

        let result = try await connection.execute("SELECT id FROM t WHERE id = ?", parameters: [.int(9)])
        XCTAssertEqual(result.rows.map { $0.values }, [[.int(9)]])
    }

    // MARK: - Multi-Result Sets Draining

    func testDeprecateEOFCallDrainsSecondResultSetWithRows() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "v", type: MySQLColumnType.varString), 2))
        transport.enqueue(packet(textRow(["x"]), 3))
        transport.enqueue(packet(feHeaderOKTerminator(status: moreResults), 4))
        transport.enqueue(packet(columnCount(1), 5))
        transport.enqueue(packet(columnDefinition(name: "v2", type: MySQLColumnType.varString), 6))
        transport.enqueue(packet(textRow(["y"]), 7))
        transport.enqueue(packet(feHeaderOKTerminator(status: 0), 8))

        let result = try await connection.execute("CALL p()")
        XCTAssertEqual(result.rows.map { $0.values }, [[.string("x")]])
    }

    func testDeprecateEOFCallDrainsTrailingOKWithoutResultSet() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "v", type: MySQLColumnType.varString), 2))
        transport.enqueue(packet(textRow(["x"]), 3))
        transport.enqueue(packet(feHeaderOKTerminator(status: moreResults), 4))
        transport.enqueue(packet(okPacket(affected: 0, status: 0), 5))

        let result = try await connection.execute("CALL p()")
        XCTAssertEqual(result.rows.map { $0.values }, [[.string("x")]])
    }

    func testLegacyCallDrainsSecondResultSetWithRows() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: false, packets: [])
        for packet in [packet(handshakePacket(deprecateEOF: false), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        try await connection.connect(password: nil)

        transport.enqueue(packet(columnCount(1), 1))
        transport.enqueue(packet(columnDefinition(name: "v", type: MySQLColumnType.varString), 2))
        transport.enqueue(packet(eofPacket(status: 0), 3))
        transport.enqueue(packet(textRow(["x"]), 4))
        transport.enqueue(packet(eofPacket(status: moreResults), 5))
        transport.enqueue(packet(columnCount(1), 6))
        transport.enqueue(packet(columnDefinition(name: "v2", type: MySQLColumnType.varString), 7))
        transport.enqueue(packet(eofPacket(status: 0), 8))
        transport.enqueue(packet(textRow(["y"]), 9))
        transport.enqueue(packet(eofPacket(status: 0), 10))

        let result = try await connection.execute("CALL p()")
        XCTAssertEqual(result.rows.map { $0.values }, [[.string("x")]])
    }

    // MARK: - Read-Only Enforcement

    func testReadOnlyProfileIssuesSessionReadOnlyAndBlocksWrites() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [], readOnly: true)
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        transport.enqueue(packet(okPacket(), 3))
        try await connection.connect(password: nil)

        let commands = transport.recordedWrites().compactMap { $0.dropFirst(4).first }
        XCTAssertTrue(commands.contains(MySQLPrepared.comQuery), "expected the read-only session statement to be sent")

        do {
            _ = try await connection.execute("DELETE FROM t")
            XCTFail("expected a read-only violation")
        } catch let error as SQLDriverError {
            XCTAssertEqual(error, .readOnlyViolation)
        }
    }

    func testReadOnlyConnectSurvivesServerErrorOnSessionStatement() async throws {
        let (connection, transport) = makeConnection(deprecateEOF: true, packets: [], readOnly: true)
        for packet in [packet(handshakePacket(deprecateEOF: true), 0), packet(okPacket(), 2)] {
            transport.enqueue(packet)
        }
        transport.enqueue(packet(errorPacket(), 3))
        try await connection.connect(password: nil)

        let connected = await connection.isConnected()
        XCTAssertTrue(connected)
    }
}
