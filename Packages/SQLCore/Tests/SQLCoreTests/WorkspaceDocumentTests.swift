import XCTest
@testable import SQLCore

final class WorkspaceDocumentTests: XCTestCase {
    func testDefaultDocument() {
        let doc = WorkspaceDocument()
        XCTAssertEqual(doc.version, WorkspaceDocument.currentVersion)
        XCTAssertTrue(doc.connections.isEmpty)
        XCTAssertTrue(doc.openTabs.isEmpty)
        XCTAssertTrue(doc.settings.autoRestoreWorkspace)
        XCTAssertTrue(doc.settings.layout.sidebarVisible)
        XCTAssertFalse(doc.settings.layout.inspectorVisible)
        XCTAssertEqual(doc.settings.layout.sidebarMode, .connections)
        XCTAssertEqual(doc.settings.resultRowLimit, 1000)
    }

    func testLayoutStateRoundTrip() throws {
        var layout = LayoutState(
            sidebarVisible: false,
            inspectorVisible: true,
            resultsCollapsed: true,
            focusMode: true,
            sidebarMode: .history,
            editorResultsRatio: 0.6,
            preFocusSidebarVisible: true,
            preFocusInspectorVisible: false
        )
        layout.editorResultsRatio = 0.99
        XCTAssertEqual(layout.editorResultsRatio, 0.85)

        let settings = UserSettings(tintName: "teal", layout: layout, compactGrid: true)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(decoded.tintName, "teal")
        XCTAssertTrue(decoded.compactGrid)
        XCTAssertEqual(decoded.layout.sidebarMode, .history)
        XCTAssertTrue(decoded.layout.inspectorVisible)
        XCTAssertFalse(decoded.layout.sidebarVisible)
    }

    func testEditorTabTitleFlags() throws {
        let untitled = EditorTabState(title: "Untitled Query")
        XCTAssertTrue(untitled.isDefaultUntitledTitle)
        XCTAssertFalse(untitled.titleIsCustom)

        let numbered = EditorTabState(title: "Untitled Query 3")
        XCTAssertTrue(numbered.isDefaultUntitledTitle)

        let named = EditorTabState(title: "users", titleIsCustom: true)
        XCTAssertFalse(named.isDefaultUntitledTitle)
        XCTAssertTrue(named.titleIsCustom)

        let data = try JSONEncoder().encode(named)
        let decoded = try JSONDecoder().decode(EditorTabState.self, from: data)
        XCTAssertEqual(decoded, named)

        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"old","sql":"SELECT 1"}
        """.data(using: .utf8)!
        let legacyTab = try JSONDecoder().decode(EditorTabState.self, from: legacy)
        XCTAssertFalse(legacyTab.titleIsCustom)
        XCTAssertEqual(legacyTab.sql, "SELECT 1")
    }

    func testLegacySettingsDecodeWithoutLayout() throws {
        let json = """
        {"tintName":null,"autoRestoreWorkspace":true,"confirmBeforeDisconnect":false}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(UserSettings.self, from: json)
        XCTAssertTrue(settings.layout.sidebarVisible)
        XCTAssertFalse(settings.layout.inspectorVisible)
        XCTAssertFalse(settings.confirmBeforeDisconnect)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.copySelectedRowsFormat, .tsv)
        XCTAssertEqual(settings.resultRowLimit, 1000)
    }

    func testResultRowLimitRoundTripAndOff() throws {
        let limited = UserSettings(resultRowLimit: 10000)
        let limitedDecoded = try JSONDecoder().decode(UserSettings.self, from: try JSONEncoder().encode(limited))
        XCTAssertEqual(limitedDecoded.resultRowLimit, 10000)

        let off = UserSettings(resultRowLimit: nil)
        let offDecoded = try JSONDecoder().decode(UserSettings.self, from: try JSONEncoder().encode(off))
        XCTAssertNil(offDecoded.resultRowLimit)

        let explicitNull = """
        {"resultRowLimit":null}
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(UserSettings.self, from: explicitNull).resultRowLimit)
    }

    func testEditorTabFileURLDecodesDefaultNil() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"old","sql":"SELECT 1"}
        """.data(using: .utf8)!
        let tab = try JSONDecoder().decode(EditorTabState.self, from: legacy)
        XCTAssertNil(tab.fileURL)

        let withFile = EditorTabState(title: "q", fileURL: URL(fileURLWithPath: "/tmp/q.sql"))
        let decoded = try JSONDecoder().decode(EditorTabState.self, from: try JSONEncoder().encode(withFile))
        XCTAssertEqual(decoded.fileURL?.path, "/tmp/q.sql")
    }

    func testCopySelectedRowsFormatRoundTrip() throws {
        let settings = UserSettings(copySelectedRowsFormat: .json)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(decoded.copySelectedRowsFormat, .json)
    }

    func testAppearanceModeCycle() {
        XCTAssertEqual(AppearanceMode.system.next, .light)
        XCTAssertEqual(AppearanceMode.light.next, .dark)
        XCTAssertEqual(AppearanceMode.dark.next, .system)
    }

    func testProfileDefaults() {
        let profile = ConnectionProfile(name: "Local", kind: .postgres)
        XCTAssertEqual(profile.port, 5432)
        XCTAssertEqual(ConnectionProfile(name: "Local", kind: .mysql).port, 3306)
        XCTAssertEqual(ConnectionProfile(name: "Local", kind: .sqlite).port, 0)
        XCTAssertEqual(ConnectionProfile(name: "Local", kind: .redis).port, 6379)
        XCTAssertFalse(ConnectionProfile(name: "Local", kind: .postgres).readOnly)
    }

    func testProfileReadOnlyDecodesDefaultFalse() throws {
        let profile = ConnectionProfile(name: "Prod", kind: .postgres, host: "db", readOnly: true)
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        XCTAssertTrue(decoded.readOnly)

        struct Legacy: Encodable {
            var id = UUID()
            var name = "Old"
            var kind = "postgres"
            var host = "h"
            var port = 5432
            var database = "db"
            var username = "u"
        }
        let legacy = try JSONEncoder().encode(Legacy())
        let migrated = try JSONDecoder().decode(ConnectionProfile.self, from: legacy)
        XCTAssertFalse(migrated.readOnly)
    }

    func testWorkspaceStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceDocumentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = WorkspaceStore(baseDirectory: dir)
        XCTAssertNil(try store.load())

        let profile = ConnectionProfile(name: "Prod", kind: .postgres, host: "db.internal", database: "app")
        let doc = WorkspaceDocument(
            connections: [profile],
            openTabs: [EditorTabState(title: "q1", connectionProfileID: profile.id, sql: "SELECT 1;")],
            selectedTabID: profile.id,
            settings: UserSettings(tintName: "indigo")
        )
        try store.save(doc)

        let loaded = try store.load()
        XCTAssertEqual(loaded, doc)

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testCodableStability() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceDocumentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = WorkspaceStore(baseDirectory: dir)
        let doc = WorkspaceDocument(
            connections: [
                ConnectionProfile(
                    name: "Tunneled",
                    kind: .mysql,
                    host: "localhost",
                    database: "shop",
                    username: "root",
                    useSSH: true,
                    ssh: SSHTunnelConfiguration(host: "bastion.corp", username: "dev")
                )
            ],
            openTabs: [EditorTabState(title: "t", sql: "SELECT 'héllo';")]
        )
        try store.save(doc)
        XCTAssertEqual(try store.load(), doc)
    }
}
