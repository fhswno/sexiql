import CryptoKit
import Foundation
import Security

public protocol CredentialStore: Sendable {
    func setPassword(_ password: String, for profileID: UUID) throws
    func password(for profileID: UUID) throws -> String?
    func deletePassword(for profileID: UUID) throws
}

public enum CredentialStoreError: Error, Sendable {
    case unhandledStatus(OSStatus)
    case vaultCorrupted
    case ioFailed(String)
}

public struct KeychainCredentialStore: CredentialStore {
    private let vault: EncryptedCredentialVault
    private let legacyKeychain = LegacyLoginKeychainStore()

    public init(directory: URL? = nil) {
        self.vault = EncryptedCredentialVault(directory: directory)
    }

    public func setPassword(_ password: String, for profileID: UUID) throws {
        try vault.setPassword(password, for: profileID)
        try? legacyKeychain.deletePassword(for: profileID)
    }

    public func password(for profileID: UUID) throws -> String? {
        if let password = try vault.password(for: profileID) {
            return password
        }
        if let legacy = try? legacyKeychain.password(for: profileID) {
            try? vault.setPassword(legacy, for: profileID)
            try? legacyKeychain.deletePassword(for: profileID)
            return legacy
        }
        return nil
    }

    public func deletePassword(for profileID: UUID) throws {
        try vault.deletePassword(for: profileID)
        try? legacyKeychain.deletePassword(for: profileID)
    }
}

// MARK: - Encrypted file vault

struct EncryptedCredentialVault: Sendable {
    private let directory: URL
    private let vaultURL: URL
    private let keyURL: URL

    init(directory: URL? = nil) {
        let base: URL
        if let directory {
            base = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            base = appSupport.appendingPathComponent("SexiQL", isDirectory: true)
        }
        self.directory = base
        self.vaultURL = base.appendingPathComponent("credentials.vault", isDirectory: false)
        self.keyURL = base.appendingPathComponent("credentials.key", isDirectory: false)
    }

    func setPassword(_ password: String, for profileID: UUID) throws {
        var items = try loadItems()
        items[profileID.uuidString] = password
        try saveItems(items)
    }

    func password(for profileID: UUID) throws -> String? {
        try loadItems()[profileID.uuidString]
    }

    func deletePassword(for profileID: UUID) throws {
        var items = try loadItems()
        guard items.removeValue(forKey: profileID.uuidString) != nil else { return }
        try saveItems(items)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        try ensureDirectory()
        if FileManager.default.fileExists(atPath: keyURL.path) {
            let data = try Data(contentsOf: keyURL)
            guard data.count == 32 else { throw CredentialStoreError.vaultCorrupted }
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try data.write(to: keyURL, options: .atomic)
        try Self.restrictToOwner(keyURL)
        return key
    }

    private func loadItems() throws -> [String: String] {
        try ensureDirectory()
        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return [:] }
        let blob = try Data(contentsOf: vaultURL)
        guard blob.count > 12 else { throw CredentialStoreError.vaultCorrupted }
        let key = try loadOrCreateKey()
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(combined: blob)
        } catch {
            throw CredentialStoreError.vaultCorrupted
        }
        let plain: Data
        do {
            plain = try AES.GCM.open(sealed, using: key)
        } catch {
            throw CredentialStoreError.vaultCorrupted
        }
        let object = try JSONSerialization.jsonObject(with: plain)
        guard let dict = object as? [String: String] else { throw CredentialStoreError.vaultCorrupted }
        return dict
    }

    private func saveItems(_ items: [String: String]) throws {
        try ensureDirectory()
        let key = try loadOrCreateKey()
        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw CredentialStoreError.ioFailed("Failed to seal credential vault")
        }
        try combined.write(to: vaultURL, options: .atomic)
        try Self.restrictToOwner(vaultURL)
        try Self.restrictToOwner(keyURL)
    }

    private static func restrictToOwner(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

// MARK: - Legacy login keychain (read/migrate only)

struct LegacyLoginKeychainStore: Sendable {
    private static let service = "com.sexiql.app"

    func password(for profileID: UUID) throws -> String? {
        return nil
    }

    func deletePassword(for profileID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
