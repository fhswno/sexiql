import XCTest
@testable import SQLCore

final class ConnectionURLParserTests: XCTestCase {
    func testPostgresURL() {
        let c = ConnectionURLParser.parse("postgres://alice:s3cret@db.example.com:5433/app?sslmode=require")
        XCTAssertEqual(c?.kind, .postgres)
        XCTAssertEqual(c?.host, "db.example.com")
        XCTAssertEqual(c?.port, 5433)
        XCTAssertEqual(c?.database, "app")
        XCTAssertEqual(c?.username, "alice")
        XCTAssertEqual(c?.password, "s3cret")
        XCTAssertEqual(c?.tlsMode, .required)
        XCTAssertEqual(c?.tlsMode?.verifiesCertificate, false)
    }

    func testSSLModeVerifyFull() {
        let c = ConnectionURLParser.parse("postgres://u@h/db?sslmode=verify-full")
        XCTAssertEqual(c?.tlsMode, .verifyFull)
        XCTAssertEqual(c?.tlsMode?.verifiesCertificate, true)
    }

    func testPostgresqlAlias() {
        let c = ConnectionURLParser.parse("postgresql://localhost/mydb")
        XCTAssertEqual(c?.kind, .postgres)
        XCTAssertEqual(c?.host, "localhost")
        XCTAssertEqual(c?.database, "mydb")
    }

    func testMySQLURL() {
        let c = ConnectionURLParser.parse("mysql://root:pass@127.0.0.1:3307/shop")
        XCTAssertEqual(c?.kind, .mysql)
        XCTAssertEqual(c?.host, "127.0.0.1")
        XCTAssertEqual(c?.port, 3307)
        XCTAssertEqual(c?.database, "shop")
        XCTAssertEqual(c?.username, "root")
        XCTAssertEqual(c?.password, "pass")
    }

    func testSQLiteURL() {
        let c = ConnectionURLParser.parse("sqlite:////tmp/test.db")
        XCTAssertEqual(c?.kind, .sqlite)
        XCTAssertEqual(c?.database, "/tmp/test.db")
    }

    func testBareHostIsNotURL() {
        XCTAssertNil(ConnectionURLParser.parse("db.internal"))
        XCTAssertFalse(ConnectionURLParser.looksLikeURL("db.internal"))
    }

    func testPasswordWithSpecialChars() {
        let c = ConnectionURLParser.parse("postgres://user:p%40ss%3Aword@host/db")
        XCTAssertEqual(c?.username, "user")
        XCTAssertEqual(c?.password, "p@ss:word")
        XCTAssertEqual(c?.host, "host")
        XCTAssertEqual(c?.database, "db")
    }

    func testJdbcPrefix() {
        let c = ConnectionURLParser.parse("jdbc:postgresql://h:5432/d")
        XCTAssertEqual(c?.kind, .postgres)
        XCTAssertEqual(c?.host, "h")
        XCTAssertEqual(c?.port, 5432)
        XCTAssertEqual(c?.database, "d")
    }
}
