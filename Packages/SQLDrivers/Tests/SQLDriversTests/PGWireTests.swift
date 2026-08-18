import XCTest
@testable import SQLDrivers

final class PGWireTests: XCTestCase {
    func testFrameStructure() {
        let frame = PGWire.frame(PGMessageType.query.rawValue, Data("SELECT 1".utf8))
        XCTAssertEqual(frame.count, 5 + 8)
        XCTAssertEqual(frame[frame.startIndex], PGMessageType.query.rawValue)
        var reader = PGByteReader(data: frame, offset: 1)
        XCTAssertEqual(try? reader.readInt32(), 12)
    }

    func testFrameUntagged() {
        let frame = PGWire.frameUntagged(PGWire.int32(196608))
        var reader = PGByteReader(data: frame)
        XCTAssertEqual(try? reader.readInt32(), 8)
        XCTAssertEqual(try? reader.readInt32(), 196608)
    }

    func testInt32BigEndian() {
        let data = PGWire.int32(196608)
        XCTAssertEqual(data.map { $0 }, [0, 3, 0, 0])
    }

    func testByteReaderRoundTrip() throws {
        var payload = Data()
        payload.append(PGWire.int16(2))
        payload.append(PGWire.cstring("hello"))
        payload.append(PGWire.int32(-1))

        var reader = PGByteReader(data: payload)
        XCTAssertEqual(try reader.readInt16(), 2)
        XCTAssertEqual(try reader.readCString(), "hello")
        XCTAssertEqual(try reader.readInt32(), -1)
        XCTAssertTrue(reader.isAtEnd)
    }

    func testByteReaderUnalignedSlice() throws {
        var padded = Data([0xFF])
        padded.append(PGWire.int16(5))
        padded.append(PGWire.int32(0x01020304))
        var reader = PGByteReader(data: Data(padded.dropFirst()), offset: 0)
        XCTAssertEqual(try reader.readInt16(), 5)
        XCTAssertEqual(try reader.readInt32(), 0x01020304)

        var signed = Data([0xAA])
        signed.append(PGWire.int16(-1))
        signed.append(PGWire.int32(-2))
        var signedReader = PGByteReader(data: Data(signed.dropFirst()))
        XCTAssertEqual(try signedReader.readInt16(), -1)
        XCTAssertEqual(try signedReader.readInt32(), -2)
    }

    func testByteReaderTruncation() {
        var reader = PGByteReader(data: Data([0x00, 0x01]))
        XCTAssertThrowsError(try reader.readInt32())
    }

    func testErrorResponseParsing() throws {
        var payload = Data()
        payload.append(0x53); payload.append(PGWire.cstring("ERROR"))
        payload.append(0x43); payload.append(PGWire.cstring("42P01"))
        payload.append(0x4D); payload.append(PGWire.cstring("relation \"t\" does not exist"))
        payload.append(0x44); payload.append(PGWire.cstring("This table is missing."))
        payload.append(0x48); payload.append(PGWire.cstring("Create it first."))
        payload.append(0x00)

        let error = try PGRowCodec.parseErrorResponse(payload)
        XCTAssertEqual(error.code, "42P01")
        XCTAssertEqual(error.message, "relation \"t\" does not exist")
        XCTAssertEqual(error.detail, "This table is missing.")
        XCTAssertEqual(error.hint, "Create it first.")
        XCTAssertEqual(try PostgresConnection.parseErrorResponse(payload).code, "42P01")
    }

    func testCommandTagParsing() {
        XCTAssertEqual(PGRowCodec.affectedRows(from: "SELECT 42"), 42)
        XCTAssertEqual(PGRowCodec.affectedRows(from: "INSERT 0 5"), 5)
        XCTAssertEqual(PGRowCodec.affectedRows(from: "UPDATE 3"), 3)
        XCTAssertEqual(PGRowCodec.affectedRows(from: "CREATE TABLE"), nil)
        XCTAssertEqual(PostgresConnection.affectedRows(from: "UPDATE 3"), 3)
    }

    func testExtendedQueryBindNullAndInt() {
        let payloads = PGQueryMessages.extendedQuery(sql: "SELECT $1", parameters: [.null, .int(7)])
        XCTAssertTrue(payloads.bind.contains(PGWire.int32(-1)))
        let seven = Data("7".utf8)
        XCTAssertTrue(payloads.bind.range(of: seven) != nil)
        XCTAssertEqual(payloads.sync, Data())
    }

    func testTextEncoding() {
        XCTAssertEqual(PGRowCodec.textEncoding(.bool(true)), "t")
        XCTAssertEqual(PGRowCodec.textEncoding(.int(42)), "42")
        XCTAssertEqual(PGRowCodec.textEncoding(.string("hi")), "hi")
    }

    func testSimpleQueryPayloadPreservesJSONAndComparison() {
        let sql = """
        SELECT id, state, created_at, started_at, completed_at, tracking_id
        FROM q_events
        WHERE event = 'Nightly Sync > Client'
          AND input->>'client' = 'ironclad'
        ORDER BY created_at DESC
        LIMIT 10
        """
        let payload = PGQueryMessages.simpleQueryPayload(sql)
        XCTAssertEqual(payload.last, 0)
        let decoded = String(decoding: payload.dropLast(), as: UTF8.self)
        XCTAssertEqual(decoded, sql)
        XCTAssertTrue(decoded.contains("->>'client'"))
        XCTAssertTrue(decoded.contains("Nightly Sync > Client"))
    }

    func testRetryableSendFailureClassification() {
        XCTAssertTrue(PGError(code: "08006", message: "Postgres write failed").isRetryableSendFailure)
        XCTAssertTrue(PGError(code: "08006", message: "Postgres output stream is closed").isRetryableSendFailure)
        XCTAssertTrue(PGError(code: "08006", message: "Not connected").isRetryableSendFailure)
        XCTAssertFalse(PGError(code: "08006", message: "Postgres read failed").isRetryableSendFailure)
        XCTAssertFalse(PGError(code: "08006", message: "Postgres server closed the connection").isRetryableSendFailure)
        XCTAssertFalse(PGError(code: "08006", message: "Connection closed by server").isRetryableSendFailure)
        XCTAssertFalse(PGError(code: "08006", message: "Timed out waiting for Postgres server response after 30s").isRetryableSendFailure)
        XCTAssertFalse(PGError(code: "42P01", message: "relation \"t\" does not exist").isRetryableSendFailure)
    }

    func testParseRowDescriptionWithTypmodMinusOne() throws {
        var payload = Data()
        payload.append(PGWire.int16(2))
        payload.append(PGWire.cstring("id"))
        payload.append(PGWire.int32(16405))
        payload.append(PGWire.int16(1))
        payload.append(PGWire.int32(23))
        payload.append(PGWire.int16(4))
        payload.append(PGWire.int32(-1))
        payload.append(PGWire.int16(0))
        payload.append(PGWire.cstring("default_pull_id"))
        payload.append(PGWire.int32(0))
        payload.append(PGWire.int16(0))
        payload.append(PGWire.int32(25))
        payload.append(PGWire.int16(-1))
        payload.append(PGWire.int32(-1))
        payload.append(PGWire.int16(0))

        var padded = Data([0xEE])
        padded.append(payload)
        let sliced = Data(padded.dropFirst())
        let columns = try PGRowCodec.parseRowDescription(sliced)
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns[0].name, "id")
        XCTAssertEqual(columns[0].dataType, "int4")
        XCTAssertEqual(columns[0].tableOID, 16405)
        XCTAssertEqual(columns[1].name, "default_pull_id")
        XCTAssertEqual(columns[1].dataType, "text")
    }

    func testParseRowDescriptionHighBitOID() throws {
        var payload = Data()
        payload.append(PGWire.int16(1))
        payload.append(PGWire.cstring("x"))
        payload.append(contentsOf: [0x80, 0x00, 0x00, 0x01])
        payload.append(PGWire.int16(1))
        payload.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFE])
        payload.append(PGWire.int16(-1))
        payload.append(PGWire.int32(-1))
        payload.append(PGWire.int16(0))
        let columns = try PGRowCodec.parseRowDescription(payload)
        XCTAssertEqual(columns[0].tableOID, 0x8000_0001)
        XCTAssertEqual(columns[0].dataType, "oid:4294967294")
    }

    func testConnectionDropClassification() {
        XCTAssertTrue(PGError(code: "08006", message: "Postgres input stream is closed").isConnectionDrop)
        XCTAssertTrue(PGError(code: "08006", message: "Postgres output stream is closed").isConnectionDrop)
        XCTAssertTrue(PGError(code: "08006", message: "Connection closed by server").isConnectionDrop)
        XCTAssertFalse(PGError(code: "08006", message: "Postgres input stream is closed").isRetryableSendFailure)
        XCTAssertFalse(PGError(code: "42P01", message: "relation \"t\" does not exist").isConnectionDrop)
        XCTAssertFalse(PGError(code: "57014", message: "canceling statement due to user request").isConnectionDrop)
    }
}

final class PGTypeTests: XCTestCase {
    func testBools() {
        XCTAssertEqual(parsePGValue(text: "t", oid: 16), .bool(true))
        XCTAssertEqual(parsePGValue(text: "f", oid: 16), .bool(false))
    }

    func testInts() {
        XCTAssertEqual(parsePGValue(text: "42", oid: 23), .int(42))
        XCTAssertEqual(parsePGValue(text: "-7", oid: 20), .int(-7))
        XCTAssertEqual(parsePGValue(text: "abc", oid: 23), .string("abc"))
    }

    func testFloats() {
        XCTAssertEqual(parsePGValue(text: "3.5", oid: 701), .double(3.5))
    }

    func testByteaHex() {
        XCTAssertEqual(parsePGValue(text: "\\xDEADBEEF", oid: 17), .data(Data([0xDE, 0xAD, 0xBE, 0xEF])))
    }

    func testStrings() {
        XCTAssertEqual(parsePGValue(text: "hi", oid: 25), .string("hi"))
        XCTAssertEqual(parsePGValue(text: "12.34", oid: 1700), .string("12.34"))
        XCTAssertEqual(parsePGValue(text: "2024-01-01", oid: 1082), .string("2024-01-01"))
        XCTAssertEqual(parsePGValue(text: "550e8400-e29b-41d4-a716-446655440000", oid: 2950), .string("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertEqual(parsePGValue(text: "x", oid: 99999), .string("x"))
    }

    func testTypeDisplayNames() {
        XCTAssertEqual(PGTypeID(rawValue: 23)?.displayName, "int4")
        XCTAssertEqual(PGTypeID(rawValue: 25)?.displayName, "text")
        XCTAssertEqual(PGTypeID(rawValue: 114)?.displayName, "json")
    }
}

final class PGSCRAMTests: XCTestCase {
    func testRFC7677Vector() throws {
        let client = SCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")

        XCTAssertEqual(client.clientFirstMessage(), "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")

        let serverFirst = try SCRAMClient.parseServerFirst(
            "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
        )
        XCTAssertEqual(serverFirst.iterations, 4096)
        XCTAssertEqual(serverFirst.salt, Data(base64Encoded: "W22ZaJ0SNY7soEsUEjb6gQ=="))

        let result = try client.clientFinalMessage(serverFirst: serverFirst)
        XCTAssertEqual(
            result.clientFinal,
            "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
        )
        XCTAssertEqual(
            result.serverSignature.base64EncodedString(),
            "6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4="
        )
    }

    func testServerFinalVerification() throws {
        let client = SCRAMClient(username: "user", password: "pencil", clientNonce: "rOprNGfwEbeRWgbNEkqO")
        let serverFirst = try SCRAMClient.parseServerFirst(
            "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
        )
        let result = try client.clientFinalMessage(serverFirst: serverFirst)

        XCTAssertTrue(SCRAMClient.verifyServerFinal("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=", expected: result.serverSignature))
        XCTAssertFalse(SCRAMClient.verifyServerFinal("v=AAAA", expected: result.serverSignature))
        XCTAssertFalse(SCRAMClient.verifyServerFinal("garbage", expected: result.serverSignature))
    }

    func testMalformedServerFirst() {
        XCTAssertThrowsError(try SCRAMClient.parseServerFirst("r=nosalt"))
        XCTAssertThrowsError(try SCRAMClient.parseServerFirst("r=x,s=!!!,i=4096"))
    }

    func testMD5PasswordDeterministic() {
        let salt = Data([0x01, 0x02, 0x03, 0x04])
        let a = pgMD5Password(password: "secret", username: "bob", salt: salt)
        let b = pgMD5Password(password: "secret", username: "bob", salt: salt)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("md5"))
        XCTAssertEqual(a.count, 35)
        XCTAssertNotEqual(a, pgMD5Password(password: "secret", username: "alice", salt: salt))
        XCTAssertNotEqual(a, pgMD5Password(password: "secret", username: "bob", salt: Data([0x09, 0x09, 0x09, 0x09])))
    }

    func testUsernameEscaping() {
        let client = SCRAMClient(username: "a=b,c", password: "x", clientNonce: "n")
        XCTAssertEqual(client.clientFirstMessageBare, "n=a=3Db=2Cc,r=n")
    }
}
