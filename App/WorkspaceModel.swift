import AppKit
import Foundation
import Observation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

@MainActor
@Observable
final class WorkspaceModel {
    var document: WorkspaceDocument
    var selectedTabID: UUID?
    var selectedConnectionID: UUID?
    var showingConnectionEditor = false
    var showingSaveQuerySheet = false
    var pendingSaveSQL: String = ""
    var pendingSaveSuggestedName: String = ""
    var editingProfile: ConnectionProfile?
    var tabTexts: [UUID: String] = [:]
    private(set) var editorContentEpoch: UInt64 = 0
    var activeSQLProvider: (() -> String?)?
    var activeEditorInsert: ((UUID, String) -> Bool)?
    var results: [UUID: [StatementResult]] = [:]
    var selectedResultIndex: [UUID: Int] = [:]
    var schemaTables: [String] = []
    var schemaObjects: [SchemaObject] = []
    var schemaColumnsByID: [String: [SchemaColumn]] = [:]
    var schemaIndexesByID: [String: [SchemaIndex]] = [:]
    var schemaForeignKeysByID: [String: [SchemaForeignKey]] = [:]
    var schemaExpandedIDs: Set<String> = []
    var schemaByProfile: [UUID: (objects: [SchemaObject], columns: [String: [SchemaColumn]])] = [:]
    var schemaFilter: String = ""
    var schemaError: String?
    var isSchemaLoading = false
    var schemaPrefetchTask: Task<Void, Never>?
    var refreshEditorCompletion: (() -> Void)?
    var formatActiveEditor: (() -> Void)?
    var showFindInEditor: (() -> Void)?

    var runningTabs: Set<UUID> = []
    var runTasks: [UUID: Task<Void, Never>] = [:]

    var busyProfileID: UUID?
    var activeError: String?

    var connectionFailure: ConnectionFailure?
    var historySearch: String = ""
    var editableTable: EditableTable?
    var isResolvingEditable = false
    var editingMessage: String?
    var showingImportSheet = false
    var importSession: ImportSession?
    var explainPlans: [UUID: ExplainNode] = [:]
    var explainErrors: [UUID: String] = [:]
    var explainingTabs: Set<UUID> = []

    var aiChatMessages: [UUID: [AIChatMessage]] = [:]
    var aiError: [UUID: String] = [:]
    var aiStreamingTabs: Set<UUID> = []

    var aiPanelVisible = false

    var showingAISetup = false
    var aiSetupReason: AISetupReason?

    var pendingAIWork: PendingAIWork?
    var editorAIComposerVisible = false
    var editorAIPrompt = ""
    var editorAIBusy = false
    var editorAIStatus: String?
    var editorAIInsert: ((UUID, String?) -> (start: Int, original: String)?)?
    var editorAIApply: ((UUID, Int, String) -> Void)?
    var editorAIFinish: ((UUID) -> Void)?
    var editorAICancelInsert: ((UUID, Int, String) -> Void)?
    var editorAIReplaceStatement: ((UUID, String, String) -> Bool)?
    var editorAITask: Task<Void, Never>?
    var editorAIRaw = ""
    var ollamaModels: [String] = []
    var ollamaModelsError: String?
    var isLoadingOllamaModels = false

    let store: WorkspaceStore
    let credentialStore: any CredentialStore
    let connectionManager: ConnectionManager
    var connectionStatuses: [UUID: ConnectionManager.SessionStatus] = [:]
    var connectTasks: [UUID: Task<Void, Never>] = [:]

    var lastConnectionErrors: [UUID: String] = [:]
    var pendingWorkspaceSave: DispatchWorkItem?
    var aiTasks: [UUID: Task<Void, Never>] = [:]
    var pendingTabRenameID: UUID?
    var settingsFocusSection: SettingsSection?
    var showingSettingsSearch = false
    var copySelectedRowsHandler: (() -> Void)?
    var addResultRowHandler: (() -> Void)?
    var deleteResultRowsHandler: (() -> Void)?
    var pendingDisconnect: ConnectionProfile?
    var pendingDeleteRows: (tabID: UUID, resultIndex: Int, rows: [Int])?
    private var didRestoreConnections = false
    var canCopySelectedRows: Bool { copySelectedRowsHandler != nil }
    var canAddResultRow: Bool { addResultRowHandler != nil }
    var canDeleteResultRows: Bool { deleteResultRowsHandler != nil }

    func isQueryRunning(on tabID: UUID?) -> Bool {
        guard let tabID else { return false }
        if runningTabs.contains(tabID) { return true }
        guard let results = results[tabID] else { return false }
        return results.contains { $0.status == .running || $0.status == .streaming || $0.status == .pending }
            && runTasks[tabID] != nil
    }

    init(
        store: WorkspaceStore = WorkspaceStore(),
        credentialStore: any CredentialStore = KeychainCredentialStore()
    ) {
        self.store = store
        self.credentialStore = credentialStore
        self.connectionManager = ConnectionManager(credentialStore: credentialStore)
        self.document = (try? store.load()) ?? WorkspaceDocument()
        if document.settings.autoRestoreWorkspace {
            selectedTabID = document.selectedTabID ?? document.openTabs.first?.id
            selectedConnectionID = document.selectedConnectionID
            for tab in document.openTabs {
                tabTexts[tab.id] = tab.sql
            }
        } else {
            document.openTabs = []
            document.selectedTabID = nil
            selectedTabID = nil
            let tab = EditorTabState(title: "Untitled Query", sql: "", titleIsCustom: false)
            document.openTabs = [tab]
            selectedTabID = tab.id
            tabTexts[tab.id] = ""
        }
        if document.openTabs.isEmpty {
            let tab = EditorTabState(title: "Untitled Query", sql: "", titleIsCustom: false)
            document.openTabs = [tab]
            selectedTabID = tab.id
            tabTexts[tab.id] = ""
        }
        bumpEditorContentEpoch()
    }

    func restoreLiveConnectionsIfNeeded() {
        guard !didRestoreConnections else { return }
        didRestoreConnections = true
        guard document.settings.autoRestoreWorkspace else { return }
        var ids = document.reconnectProfileIDs
        if let selected = document.selectedConnectionID {
            ids.append(selected)
        }
        ids.append(contentsOf: document.openTabs.compactMap(\.connectionProfileID))
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            guard let profile = document.connections.first(where: { $0.id == id }) else { continue }
            reconnectQuietly(profile)
        }
    }

    func bumpEditorContentEpoch() {
        editorContentEpoch &+= 1
    }

    func setTabTextExternal(_ tabID: UUID, sql: String) {
        tabTexts[tabID] = sql
        bumpEditorContentEpoch()
    }
}
