import Foundation

public enum SidebarMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case connections
    case schema
    case saved
    case history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .connections: "Connections"
        case .schema: "Schema"
        case .saved: "Saved"
        case .history: "History"
        }
    }

    public var systemImage: String {
        switch self {
        case .connections: "externaldrive.connected.to.line.below"
        case .schema: "tablecells"
        case .saved: "bookmark"
        case .history: "clock"
        }
    }
}

public struct LayoutState: Codable, Sendable, Equatable {
    public var sidebarVisible: Bool
    public var inspectorVisible: Bool
    public var resultsCollapsed: Bool
    public var focusMode: Bool
    public var sidebarMode: SidebarMode
    public var editorResultsRatio: Double {
        didSet { editorResultsRatio = Self.clampRatio(editorResultsRatio) }
    }
    public var preFocusSidebarVisible: Bool?
    public var preFocusInspectorVisible: Bool?

    public static func clampRatio(_ value: Double) -> Double {
        min(max(value, 0.15), 0.85)
    }

    public init(
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = false,
        resultsCollapsed: Bool = false,
        focusMode: Bool = false,
        sidebarMode: SidebarMode = .connections,
        editorResultsRatio: Double = 0.45,
        preFocusSidebarVisible: Bool? = nil,
        preFocusInspectorVisible: Bool? = nil
    ) {
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
        self.resultsCollapsed = resultsCollapsed
        self.focusMode = focusMode
        self.sidebarMode = sidebarMode
        self.editorResultsRatio = Self.clampRatio(editorResultsRatio)
        self.preFocusSidebarVisible = preFocusSidebarVisible
        self.preFocusInspectorVisible = preFocusInspectorVisible
    }

    private enum CodingKeys: String, CodingKey {
        case sidebarVisible, inspectorVisible, resultsCollapsed, focusMode
        case sidebarMode, editorResultsRatio
        case preFocusSidebarVisible, preFocusInspectorVisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? true
        inspectorVisible = try container.decodeIfPresent(Bool.self, forKey: .inspectorVisible) ?? false
        resultsCollapsed = try container.decodeIfPresent(Bool.self, forKey: .resultsCollapsed) ?? false
        focusMode = try container.decodeIfPresent(Bool.self, forKey: .focusMode) ?? false
        sidebarMode = try container.decodeIfPresent(SidebarMode.self, forKey: .sidebarMode) ?? .connections
        let ratio = try container.decodeIfPresent(Double.self, forKey: .editorResultsRatio) ?? 0.45
        editorResultsRatio = Self.clampRatio(ratio)
        preFocusSidebarVisible = try container.decodeIfPresent(Bool.self, forKey: .preFocusSidebarVisible)
        preFocusInspectorVisible = try container.decodeIfPresent(Bool.self, forKey: .preFocusInspectorVisible)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sidebarVisible, forKey: .sidebarVisible)
        try container.encode(inspectorVisible, forKey: .inspectorVisible)
        try container.encode(resultsCollapsed, forKey: .resultsCollapsed)
        try container.encode(focusMode, forKey: .focusMode)
        try container.encode(sidebarMode, forKey: .sidebarMode)
        try container.encode(editorResultsRatio, forKey: .editorResultsRatio)
        try container.encodeIfPresent(preFocusSidebarVisible, forKey: .preFocusSidebarVisible)
        try container.encodeIfPresent(preFocusInspectorVisible, forKey: .preFocusInspectorVisible)
    }
}

public enum CopySelectedRowsFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case tsv
    case csv
    case json

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tsv: "TSV"
        case .csv: "CSV"
        case .json: "JSON"
        }
    }
}

public enum AppearanceMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Next mode when cycling with ⌘⇧A.
    public var next: AppearanceMode {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }
}

public struct UserSettings: Codable, Sendable, Equatable {
    public var tintName: String?
    public var autoRestoreWorkspace: Bool
    public var confirmBeforeDisconnect: Bool
    public var layout: LayoutState
    public var compactGrid: Bool
    public var appearance: AppearanceMode
    public var copySelectedRowsFormat: CopySelectedRowsFormat
    public var aiEnabled: Bool
    public var ollamaBaseURL: String
    public var ollamaModel: String
    public var resultRowLimit: Int?

    public init(
        tintName: String? = nil,
        autoRestoreWorkspace: Bool = true,
        confirmBeforeDisconnect: Bool = true,
        layout: LayoutState = LayoutState(),
        compactGrid: Bool = false,
        appearance: AppearanceMode = .system,
        copySelectedRowsFormat: CopySelectedRowsFormat = .tsv,
        aiEnabled: Bool = false,
        ollamaBaseURL: String = "http://127.0.0.1:11434",
        ollamaModel: String = "",
        resultRowLimit: Int? = 1000
    ) {
        self.tintName = tintName
        self.autoRestoreWorkspace = autoRestoreWorkspace
        self.confirmBeforeDisconnect = confirmBeforeDisconnect
        self.layout = layout
        self.compactGrid = compactGrid
        self.appearance = appearance
        self.copySelectedRowsFormat = copySelectedRowsFormat
        self.aiEnabled = aiEnabled
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
        self.resultRowLimit = resultRowLimit
    }

    private enum CodingKeys: String, CodingKey {
        case tintName, autoRestoreWorkspace, confirmBeforeDisconnect, layout, compactGrid, appearance
        case copySelectedRowsFormat
        case aiEnabled, ollamaBaseURL, ollamaModel
        case resultRowLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tintName = try container.decodeIfPresent(String.self, forKey: .tintName)
        autoRestoreWorkspace = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreWorkspace) ?? true
        confirmBeforeDisconnect = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeDisconnect) ?? true
        layout = try container.decodeIfPresent(LayoutState.self, forKey: .layout) ?? LayoutState()
        compactGrid = try container.decodeIfPresent(Bool.self, forKey: .compactGrid) ?? false
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        copySelectedRowsFormat = try container.decodeIfPresent(CopySelectedRowsFormat.self, forKey: .copySelectedRowsFormat) ?? .tsv
        aiEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? false
        ollamaBaseURL = try container.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? "http://127.0.0.1:11434"
        ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? ""
        if container.contains(.resultRowLimit) {
            resultRowLimit = try container.decodeIfPresent(Int.self, forKey: .resultRowLimit)
        } else {
            resultRowLimit = 1000
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(tintName, forKey: .tintName)
        try container.encode(autoRestoreWorkspace, forKey: .autoRestoreWorkspace)
        try container.encode(confirmBeforeDisconnect, forKey: .confirmBeforeDisconnect)
        try container.encode(layout, forKey: .layout)
        try container.encode(compactGrid, forKey: .compactGrid)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(copySelectedRowsFormat, forKey: .copySelectedRowsFormat)
        try container.encode(aiEnabled, forKey: .aiEnabled)
        try container.encode(ollamaBaseURL, forKey: .ollamaBaseURL)
        try container.encode(ollamaModel, forKey: .ollamaModel)
        try container.encode(resultRowLimit, forKey: .resultRowLimit)
    }
}

public struct EditorTabState: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var connectionProfileID: UUID?
    public var sql: String
    public var titleIsCustom: Bool
    public var fileURL: URL?

    public init(
        id: UUID = UUID(),
        title: String,
        connectionProfileID: UUID? = nil,
        sql: String = "",
        titleIsCustom: Bool = false,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.connectionProfileID = connectionProfileID
        self.sql = sql
        self.titleIsCustom = titleIsCustom
        self.fileURL = fileURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, connectionProfileID, sql, titleIsCustom, fileURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        connectionProfileID = try container.decodeIfPresent(UUID.self, forKey: .connectionProfileID)
        sql = try container.decodeIfPresent(String.self, forKey: .sql) ?? ""
        titleIsCustom = try container.decodeIfPresent(Bool.self, forKey: .titleIsCustom) ?? false
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(connectionProfileID, forKey: .connectionProfileID)
        try container.encode(sql, forKey: .sql)
        try container.encode(titleIsCustom, forKey: .titleIsCustom)
        try container.encodeIfPresent(fileURL, forKey: .fileURL)
    }

    public var isDefaultUntitledTitle: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Untitled Query" { return true }
        guard trimmed.hasPrefix("Untitled Query ") else { return false }
        let suffix = trimmed.dropFirst("Untitled Query ".count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }
}

public struct QueryHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var sql: String
    public var connectionProfileID: UUID?
    public var connectionName: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sql: String,
        connectionProfileID: UUID? = nil,
        connectionName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sql = sql
        self.connectionProfileID = connectionProfileID
        self.connectionName = connectionName
        self.createdAt = createdAt
    }
}

public struct SavedQuery: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var sql: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, sql: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sql = sql
        self.createdAt = createdAt
    }
}

public struct WorkspaceDocument: Codable, Sendable, Equatable {
    public static let currentVersion = 2
    public static let historyLimit = 500

    public var version: Int
    public var connections: [ConnectionProfile]
    public var openTabs: [EditorTabState]
    public var selectedTabID: UUID?
    public var selectedConnectionID: UUID?
    public var reconnectProfileIDs: [UUID]
    public var settings: UserSettings
    public var history: [QueryHistoryEntry]
    public var savedQueries: [SavedQuery]

    public init(
        version: Int = WorkspaceDocument.currentVersion,
        connections: [ConnectionProfile] = [],
        openTabs: [EditorTabState] = [],
        selectedTabID: UUID? = nil,
        selectedConnectionID: UUID? = nil,
        reconnectProfileIDs: [UUID] = [],
        settings: UserSettings = UserSettings(),
        history: [QueryHistoryEntry] = [],
        savedQueries: [SavedQuery] = []
    ) {
        self.version = version
        self.connections = connections
        self.openTabs = openTabs
        self.selectedTabID = selectedTabID
        self.selectedConnectionID = selectedConnectionID
        self.reconnectProfileIDs = reconnectProfileIDs
        self.settings = settings
        self.history = history
        self.savedQueries = savedQueries
    }

    private enum CodingKeys: String, CodingKey {
        case version, connections, openTabs, selectedTabID, selectedConnectionID, reconnectProfileIDs
        case settings, history, savedQueries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? WorkspaceDocument.currentVersion
        connections = try container.decodeIfPresent([ConnectionProfile].self, forKey: .connections) ?? []
        openTabs = try container.decodeIfPresent([EditorTabState].self, forKey: .openTabs) ?? []
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        selectedConnectionID = try container.decodeIfPresent(UUID.self, forKey: .selectedConnectionID)
        reconnectProfileIDs = try container.decodeIfPresent([UUID].self, forKey: .reconnectProfileIDs) ?? []
        settings = try container.decodeIfPresent(UserSettings.self, forKey: .settings) ?? UserSettings()
        history = try container.decodeIfPresent([QueryHistoryEntry].self, forKey: .history) ?? []
        savedQueries = try container.decodeIfPresent([SavedQuery].self, forKey: .savedQueries) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(connections, forKey: .connections)
        try container.encode(openTabs, forKey: .openTabs)
        try container.encodeIfPresent(selectedTabID, forKey: .selectedTabID)
        try container.encodeIfPresent(selectedConnectionID, forKey: .selectedConnectionID)
        try container.encode(reconnectProfileIDs, forKey: .reconnectProfileIDs)
        try container.encode(settings, forKey: .settings)
        try container.encode(history, forKey: .history)
        try container.encode(savedQueries, forKey: .savedQueries)
    }
}
