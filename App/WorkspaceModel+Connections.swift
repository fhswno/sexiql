import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Connections

    func status(for profileID: UUID) -> ConnectionManager.SessionStatus {
        connectionStatuses[profileID] ?? .disconnected
    }

    func selectConnection(_ profile: ConnectionProfile) {
        selectedConnectionID = profile.id
        bindActiveTab(to: profile.id)
        if status(for: profile.id) == .connected {
            Task { await loadSchema(for: profile) }
        }
    }

    func bindActiveTab(to profileID: UUID?) {
        guard let tabID = selectedTabID,
              let index = document.openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        if document.openTabs[index].connectionProfileID != profileID {
            document.openTabs[index].connectionProfileID = profileID
            saveWorkspace()
        }
    }

    @discardableResult
    func ensureTabHasConnection(_ tabID: UUID) -> UUID? {
        guard let index = document.openTabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        if let existing = document.openTabs[index].connectionProfileID,
           document.connections.contains(where: { $0.id == existing }) {
            if selectedConnectionID != existing {
                selectedConnectionID = existing
            }
            return existing
        }
        if let sidebar = selectedConnectionID,
           document.connections.contains(where: { $0.id == sidebar }) {
            document.openTabs[index].connectionProfileID = sidebar
            saveWorkspace()
            return sidebar
        }
        if let connected = document.connections.first(where: { status(for: $0.id) == .connected }) {
            document.openTabs[index].connectionProfileID = connected.id
            selectedConnectionID = connected.id
            saveWorkspace()
            return connected.id
        }
        return nil
    }

    func reconnectQuietly(_ profile: ConnectionProfile) {
        guard connectTasks[profile.id] == nil else { return }
        switch status(for: profile.id) {
        case .connected, .connecting: return
        default: break
        }
        startConnect(profile, select: false)
    }

    func connect(_ profile: ConnectionProfile) {
        selectConnection(profile)
        startConnect(profile, select: true)
    }

    private func startConnect(_ profile: ConnectionProfile, select: Bool) {
        guard connectTasks[profile.id] == nil else { return }
        connectionStatuses[profile.id] = .connecting
        lastConnectionErrors[profile.id] = nil
        if connectionFailure?.profileID == profile.id {
            connectionFailure = nil
        }
        connectTasks[profile.id] = Task.detached { [connectionManager] in
            do {
                _ = try await connectionManager.connect(profile)
                await MainActor.run {
                    self.connectionStatuses[profile.id] = .connected
                    self.lastConnectionErrors[profile.id] = nil
                    self.connectTasks[profile.id] = nil
                    if select {
                        self.bindActiveTab(to: profile.id)
                    }
                    if self.selectedConnectionID == nil {
                        self.selectedConnectionID = profile.id
                    }
                    self.persistSessionToDisk()
                }
                await self.loadSchema(for: profile)
            } catch is CancellationError {
                await MainActor.run {
                    self.connectionStatuses[profile.id] = .disconnected
                    self.connectTasks[profile.id] = nil
                }
            } catch {
                await MainActor.run {
                    let technical = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    self.presentConnectionFailure(
                        profile,
                        technical: technical,
                        error: error
                    )
                    self.connectTasks[profile.id] = nil
                }
            }
        }
    }

    func requestDisconnect(_ profile: ConnectionProfile) {
        let live: Bool
        switch status(for: profile.id) {
        case .connected, .connecting: live = true
        default: live = false
        }
        if document.settings.confirmBeforeDisconnect, live {
            pendingDisconnect = profile
        } else {
            disconnect(profile)
        }
    }

    func confirmPendingDisconnect() {
        guard let profile = pendingDisconnect else { return }
        pendingDisconnect = nil
        disconnect(profile)
    }

    func cancelPendingDisconnect() {
        pendingDisconnect = nil
    }

    func disconnect(_ profile: ConnectionProfile) {
        Task {
            try? await connectionManager.disconnect(profile.id)
            connectionStatuses[profile.id] = .disconnected
            lastConnectionErrors[profile.id] = nil
            if connectionFailure?.profileID == profile.id {
                connectionFailure = nil
            }
            if selectedConnectionID == profile.id {
                schemaTables = []
            }
            persistSessionToDisk()
        }
    }

    func connectionErrorMessage(for profileID: UUID) -> String? {
        if case .failed(let message) = connectionStatuses[profileID] {
            return message
        }
        return lastConnectionErrors[profileID]
    }

    func dismissConnectionFailure() {
        connectionFailure = nil
    }

    func showConnectionFailure(for profile: ConnectionProfile) {
        let technical = connectionErrorMessage(for: profile.id) ?? "Connection failed."
        presentConnectionFailure(profile, technical: technical, autoPresent: true)
    }

    func retryConnection(for profileID: UUID) {
        guard let profile = document.connections.first(where: { $0.id == profileID }) else { return }
        connectionFailure = nil
        connect(profile)
    }

    func editConnection(for profileID: UUID) {
        guard let profile = document.connections.first(where: { $0.id == profileID }) else { return }
        connectionFailure = nil
        editingProfile = profile
        showingConnectionEditor = true
    }

    func presentConnectionFailure(
        _ profile: ConnectionProfile,
        technical: String,
        error: Error? = nil,
        autoPresent: Bool = true
    ) {
        let friendly = ConnectionErrorFormatting.userMessage(
            technical: technical,
            error: error,
            profile: profile
        )
        lastConnectionErrors[profile.id] = friendly
        connectionStatuses[profile.id] = .failed(friendly)
        let endpoint: String?
        if profile.kind == .sqlite {
            endpoint = profile.database.isEmpty ? nil : profile.database
        } else {
            let catalog = profile.displayCatalog
            let host = "\(profile.host):\(profile.port)"
            endpoint = catalog.isEmpty ? host : "\(catalog) @ \(host)"
        }
        let failure = ConnectionFailure(
            profileID: profile.id,
            connectionName: profile.name,
            engineName: profile.kind.displayName,
            endpoint: endpoint,
            message: friendly,
            technicalDetail: technical
        )
        if autoPresent {
            connectionFailure = failure
        }
    }

    func hasSavedPassword(for profileID: UUID) -> Bool {
        (try? credentialStore.password(for: profileID))?.isEmpty == false
    }

    func testConnection(_ profile: ConnectionProfile, password: String?) async -> Result<String, Error> {
        var probe = profile
        probe.id = UUID()
        if let password, !password.isEmpty {
            try? credentialStore.setPassword(password, for: probe.id)
        } else if let existing = try? credentialStore.password(for: profile.id), !existing.isEmpty {
            try? credentialStore.setPassword(existing, for: probe.id)
        }
        defer {
            try? credentialStore.deletePassword(for: probe.id)
        }
        do {
            let connection = try await connectionManager.connect(probe)
            let detail: String
            switch profile.kind {
            case .redis:
                _ = try await connection.execute("PING")
                detail = (try? await connection.serverVersion()) ?? "PONG"
            case .sqlite, .postgres, .mysql:
                _ = try await connection.execute("SELECT 1")
                detail = (try? await connection.serverVersion()) ?? "OK"
            }
            try? await connectionManager.disconnect(probe.id)
            return .success(detail)
        } catch {
            try? await connectionManager.disconnect(probe.id)
            return .failure(error)
        }
    }

    func saveProfile(_ profile: ConnectionProfile, password: String?) {
        if let index = document.connections.firstIndex(where: { $0.id == profile.id }) {
            document.connections[index] = profile
        } else {
            document.connections.append(profile)
        }
        if let password {
            try? credentialStore.setPassword(password, for: profile.id)
        }
        saveWorkspace()
    }

    func moveConnection(id: UUID, before targetID: UUID?) {
        guard id != targetID else { return }
        guard let from = document.connections.firstIndex(where: { $0.id == id }) else { return }
        var connections = document.connections
        let item = connections.remove(at: from)
        if let targetID, let to = connections.firstIndex(where: { $0.id == targetID }) {
            connections.insert(item, at: to)
        } else {
            connections.append(item)
        }
        if connections.map(\.id) == document.connections.map(\.id) { return }
        document.connections = connections
        scheduleSaveWorkspace()
    }

    func deleteProfile(_ profile: ConnectionProfile) {
        Task {
            try? await connectionManager.disconnect(profile.id)
        }
        document.connections.removeAll { $0.id == profile.id }
        try? credentialStore.deletePassword(for: profile.id)
        if selectedConnectionID == profile.id {
            selectedConnectionID = nil
            schemaTables = []
        }
        saveWorkspace()
    }

    func connection(for profileID: UUID) async -> (any DatabaseConnection)? {
        await connectionManager.connection(for: profileID)
    }

}
