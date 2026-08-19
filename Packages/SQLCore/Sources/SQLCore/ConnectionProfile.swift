import Foundation

public enum DatabaseKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case postgres
    case mysql
    case sqlite
    case redis

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .postgres: "PostgreSQL"
        case .mysql: "MySQL"
        case .sqlite: "SQLite"
        case .redis: "Redis"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .postgres: 5432
        case .mysql: 3306
        case .sqlite: 0
        case .redis: 6379
        }
    }
}

public enum TLSMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case preferred
    case required
    case verifyFull

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .preferred: "Preferred"
        case .required: "Required"
        case .verifyFull: "Verify full"
        }
    }

    public var verifiesCertificate: Bool {
        self == .verifyFull
    }
}

public struct SSHTunnelConfiguration: Codable, Sendable, Equatable {
    public enum AuthenticationMethod: String, Codable, Sendable {
        case password
        case privateKey
    }

    public var host: String
    public var port: Int
    public var username: String
    public var authentication: AuthenticationMethod
    public var privateKeyPath: String?

    public init(
        host: String,
        port: Int = 22,
        username: String,
        authentication: AuthenticationMethod = .password,
        privateKeyPath: String? = nil
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authentication = authentication
        self.privateKeyPath = privateKeyPath
    }
}

public struct ConnectionProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: DatabaseKind
    public var host: String
    public var port: Int
    public var database: String
    public var username: String
    public var tlsMode: TLSMode
    public var tlsServerName: String?
    public var useSSH: Bool
    public var ssh: SSHTunnelConfiguration?
    public var readOnly: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DatabaseKind,
        host: String = "",
        port: Int? = nil,
        database: String = "",
        username: String = "",
        tlsMode: TLSMode = .preferred,
        tlsServerName: String? = nil,
        useSSH: Bool = false,
        ssh: SSHTunnelConfiguration? = nil,
        readOnly: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port ?? kind.defaultPort
        self.database = database
        self.username = username
        self.tlsMode = tlsMode
        self.tlsServerName = tlsServerName
        self.useSSH = useSSH
        self.ssh = ssh
        self.readOnly = readOnly
        self.createdAt = createdAt
    }

    public var credentialAccount: String { id.uuidString }

    public var resolvedDatabase: String {
        let trimmed = database.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if kind == .postgres {
            return username.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    public var displayCatalog: String {
        switch kind {
        case .sqlite:
            let name = (database as NSString).lastPathComponent
            return name
        case .postgres, .mysql, .redis:
            return resolvedDatabase
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, host, port, database, username, tlsMode, tlsServerName, useSSH, ssh, readOnly, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(DatabaseKind.self, forKey: .kind)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        database = try container.decode(String.self, forKey: .database)
        username = try container.decode(String.self, forKey: .username)
        tlsMode = try container.decodeIfPresent(TLSMode.self, forKey: .tlsMode) ?? .preferred
        tlsServerName = try container.decodeIfPresent(String.self, forKey: .tlsServerName)
        useSSH = try container.decodeIfPresent(Bool.self, forKey: .useSSH) ?? false
        ssh = try container.decodeIfPresent(SSHTunnelConfiguration.self, forKey: .ssh)
        readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(database, forKey: .database)
        try container.encode(username, forKey: .username)
        try container.encode(tlsMode, forKey: .tlsMode)
        try container.encodeIfPresent(tlsServerName, forKey: .tlsServerName)
        try container.encode(useSSH, forKey: .useSSH)
        try container.encodeIfPresent(ssh, forKey: .ssh)
        try container.encode(readOnly, forKey: .readOnly)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
