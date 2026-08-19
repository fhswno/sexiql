import Foundation
import SQLCore
import SQLTunnel

enum ConnectionFactoryHook {
    nonisolated(unsafe) static var factory: ((ConnectionProfile) -> any DatabaseConnection)?
}

public actor ConnectionManager {
    public enum SessionStatus: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private final class Session: @unchecked Sendable {
        var connection: (any DatabaseConnection)?
        var tunnel: (any TunnelSession)?
        var status: SessionStatus = .disconnected
    }

    private var sessions: [UUID: Session] = [:]
    private let credentialStore: any CredentialStore

    public init(credentialStore: any CredentialStore = KeychainCredentialStore()) {
        self.credentialStore = credentialStore
    }

    public func status(for profileID: UUID) -> SessionStatus {
        sessions[profileID]?.status ?? .disconnected
    }

    public func connection(for profileID: UUID) -> (any DatabaseConnection)? {
        sessions[profileID]?.connection
    }

    public func connect(_ profile: ConnectionProfile) async throws -> any DatabaseConnection {
        if let session = sessions[profile.id], let connection = session.connection {
            if await connection.isConnected() { return connection }
        }
        let session = sessions[profile.id] ?? Session()
        sessions[profile.id] = session
        session.status = .connecting
        do {
            let password = try? credentialStore.password(for: profile.id)
            var endpointProfile = profile
            if profile.useSSH {
                let tunnel = try await SSHTunnelManager().makeSession(for: profile, password: password)
                endpointProfile = ConnectionProfile(
                    id: profile.id,
                    name: profile.name,
                    kind: profile.kind,
                    host: "127.0.0.1",
                    port: tunnel.localPort,
                    database: profile.resolvedDatabase,
                    username: profile.username,
                    tlsMode: profile.tlsMode,
                    tlsServerName: profile.host,
                    useSSH: false,
                    ssh: nil,
                    createdAt: profile.createdAt
                )
                session.tunnel = tunnel
            }
            let connection = ConnectionFactoryHook.factory?(endpointProfile) ?? ConnectionFactory().makeConnection(for: endpointProfile)
            try await connection.connect(password: password)
            session.connection = connection
            session.status = .connected
            return connection
        } catch {
            try? await session.tunnel?.stop()
            session.tunnel = nil
            session.status = .failed(error.localizedDescription)
            throw error
        }
    }

    public func disconnect(_ profileID: UUID) async throws {
        guard let session = sessions[profileID], let connection = session.connection else { return }
        try await connection.disconnect()
        try? await session.tunnel?.stop()
        session.tunnel = nil
        session.connection = nil
        session.status = .disconnected
    }

    public func disconnectAll() async {
        for session in sessions.values {
            if let connection = session.connection {
                try? await connection.disconnect()
            }
            try? await session.tunnel?.stop()
            session.tunnel = nil
            session.connection = nil
            session.status = .disconnected
        }
    }
}
