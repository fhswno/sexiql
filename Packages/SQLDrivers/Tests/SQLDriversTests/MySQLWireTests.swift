import XCTest
@testable import SQLDrivers
import SQLCore

final class MySQLWireTests: XCTestCase {
    func testLengthEncodedIntegerBoundaries() throws {
        let values: [UInt64] = [0, 250, 251, 255, 65_535, 65_536, 16_777_215, 16_777_216, UInt64.max]
        for value in values {
            var reader = MySQLByteReader(data: MySQLWire.lengthEncodedInteger(value))
            XCTAssertEqual(try reader.readLengthEncodedInteger(), value)
            XCTAssertTrue(reader.isAtEnd)
        }
    }

    func testLengthEncodedNullAndBytes() throws {
        var reader = MySQLByteReader(data: MySQLWire.lengthEncoded(nil as Data?) + MySQLWire.lengthEncoded(Data("hello".utf8)))
        XCTAssertNil(try reader.readLengthEncodedBytes())
        XCTAssertEqual(try reader.readLengthEncodedString(), "hello")
    }

    func testPacketFrame() {
        let packet = MySQLPacket(sequence: 3, payload: Data([0x03, 0x41, 0x42]))
        XCTAssertEqual(packet.encoded(), Data([3, 0, 0, 3, 3, 0x41, 0x42]))
    }

    func testHandshakeParsing() throws {
        var payload = Data([0x0a])
        payload.append(MySQLWire.cstring("8.0.36"))
        payload.append(MySQLWire.uint32(123))
        payload.append(Data("12345678".utf8))
        payload.append(0)
        payload.append(MySQLWire.uint16(0xffff))
        payload.append(33)
        payload.append(MySQLWire.uint16(2))
        payload.append(MySQLWire.uint16(0xffff))
        payload.append(21)
        payload.append(contentsOf: repeatElement(UInt8(0), count: 10))
        payload.append(Data("abcdefghijkl".utf8))
        payload.append(0)
        payload.append(MySQLWire.cstring("caching_sha2_password"))

        let handshake = try MySQLHandshake.parse(payload)
        XCTAssertEqual(handshake.protocolVersion, 10)
        XCTAssertEqual(handshake.serverVersion, "8.0.36")
        XCTAssertEqual(handshake.connectionID, 123)
        XCTAssertEqual(handshake.scramble.count, 20)
        XCTAssertEqual(handshake.authPlugin, "caching_sha2_password")
        XCTAssertTrue(handshake.capabilities.contains(.ssl))
        XCTAssertTrue(handshake.capabilities.contains(.pluginAuth))
    }

    func testAuthTokensAreStableAndSized() throws {
        let scramble = Data("12345678901234567890".utf8)
        let nativeA = try MySQLAuth.authToken(password: "secret", plugin: "mysql_native_password", scramble: scramble)
        let nativeB = try MySQLAuth.authToken(password: "secret", plugin: "mysql_native_password", scramble: scramble)
        XCTAssertEqual(nativeA, nativeB)
        XCTAssertEqual(nativeA.count, 20)

        let caching = try MySQLAuth.authToken(password: "secret", plugin: "caching_sha2_password", scramble: scramble)
        XCTAssertEqual(caching.count, 32)
        XCTAssertNotEqual(nativeA, caching)
    }

    func testUnsupportedAuthThrows() {
        XCTAssertThrowsError(try MySQLAuth.authToken(password: "x", plugin: "unknown_plugin", scramble: Data(repeating: 0, count: 20)))
    }

    func testCapabilitiesRespectTLSMode() throws {
        let handshake = MySQLHandshake(
            protocolVersion: 10,
            serverVersion: "8.0",
            connectionID: 1,
            scramble: Data(repeating: 0, count: 20),
            capabilities: [.protocol41, .ssl, .pluginAuth, .secureConnection],
            characterSet: 33,
            statusFlags: 0,
            authPlugin: "caching_sha2_password"
        )
        XCTAssertTrue(try MySQLAuth.buildCapabilities(handshake: handshake, database: "db", tlsMode: .required).contains(.ssl))

        let noTLSHandshake = MySQLHandshake(
            protocolVersion: 10,
            serverVersion: "8.0",
            connectionID: 1,
            scramble: Data(repeating: 0, count: 20),
            capabilities: [.protocol41, .pluginAuth],
            characterSet: 33,
            statusFlags: 0,
            authPlugin: "mysql_native_password"
        )
        XCTAssertThrowsError(try MySQLAuth.buildCapabilities(handshake: noTLSHandshake, database: "db", tlsMode: .required))
    }

    func testOKAndErrorPackets() throws {
        var ok = Data([0x00])
        ok.append(MySQLWire.lengthEncodedInteger(4))
        ok.append(MySQLWire.lengthEncodedInteger(9))
        ok.append(MySQLWire.uint16(2))
        XCTAssertEqual(try MySQLAuth.parseOK(ok).affectedRows, 4)

        var error = Data([0xff])
        error.append(MySQLWire.uint16(1064))
        error.append(Data("#42000".utf8))
        error.append(Data("syntax error".utf8))
        guard case .serverError(let code, let message, let state) = try MySQLAuth.parseError(error) else {
            XCTFail("expected server error")
            return
        }
        XCTAssertEqual(code, 1064)
        XCTAssertEqual(message, "syntax error")
        XCTAssertEqual(state, "42000")
    }

    func testKillQuerySQL() {
        XCTAssertEqual(MySQLCancel.killQuerySQL(connectionID: 42), "KILL QUERY 42")
        XCTAssertEqual(MySQLCancel.queryInterruptedCode, 1317)
        XCTAssertEqual(MySQLCancel.noSuchThreadCode, 1094)
    }

    func testQueryInterruptedClassification() {
        let interrupted = MySQLWireError.serverError(
            code: 1317,
            message: "Query execution was interrupted",
            state: "70100"
        )
        XCTAssertTrue(interrupted.isQueryInterrupted)
        XCTAssertFalse(MySQLCancel.isBenignKillError(interrupted))

        let byState = MySQLWireError.serverError(code: 1, message: "stopped", state: "70100")
        XCTAssertTrue(byState.isQueryInterrupted)

        let byMessage = MySQLWireError.serverError(code: 0, message: "Query execution was interrupted", state: nil)
        XCTAssertTrue(byMessage.isQueryInterrupted)

        let syntax = MySQLWireError.serverError(code: 1064, message: "syntax error", state: "42000")
        XCTAssertFalse(syntax.isQueryInterrupted)
        XCTAssertFalse(MySQLCancel.isBenignKillError(syntax))

        let gone = MySQLWireError.serverError(code: 1094, message: "Unknown thread id: 1", state: "HY000")
        XCTAssertTrue(MySQLCancel.isBenignKillError(gone))
        XCTAssertFalse(gone.isQueryInterrupted)
    }
}
