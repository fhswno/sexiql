import XCTest
@testable import SQLCore

final class KeychainCredentialStoreTests: XCTestCase {
    private var directory: URL!
    private var store: KeychainCredentialStore!
    private let profileID = UUID()

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SexiQL-cred-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = KeychainCredentialStore(directory: directory)
    }

    override func tearDown() async throws {
        try? store.deletePassword(for: profileID)
        try? FileManager.default.removeItem(at: directory)
    }

    func testSetGetDeleteRoundTrip() throws {
        try store.setPassword("s3cr3t!", for: profileID)
        XCTAssertEqual(try store.password(for: profileID), "s3cr3t!")

        try store.setPassword("updated", for: profileID)
        XCTAssertEqual(try store.password(for: profileID), "updated")

        try store.deletePassword(for: profileID)
        XCTAssertNil(try store.password(for: profileID))
    }

    func testMissingPasswordIsNil() throws {
        XCTAssertNil(try store.password(for: UUID()))
    }

    func testVaultFilesAreOwnerReadableOnly() throws {
        try store.setPassword("x", for: profileID)
        let vault = directory.appendingPathComponent("credentials.vault")
        let key = directory.appendingPathComponent("credentials.key")
        let vaultPerms = try FileManager.default.attributesOfItem(atPath: vault.path)[.posixPermissions] as? NSNumber
        let keyPerms = try FileManager.default.attributesOfItem(atPath: key.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(vaultPerms?.intValue, 0o600)
        XCTAssertEqual(keyPerms?.intValue, 0o600)
    }
}
