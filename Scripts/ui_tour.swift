import AppKit
import SwiftUI
import SQLCore
import SQLDrivers
import SQLGrid
@testable import SexiQLView

@main
struct UITour {
    @MainActor
    static func main() async {
        do {
            try await tour()
        } catch {
            fputs("UI TOUR FAILED: \(error)\n", stderr)
            exit(1)
        }
        fputs("UI TOUR PASSED\n", stderr)
        exit(0)
    }

    @MainActor
    static func tour() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITour-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let model = WorkspaceModel(
            store: WorkspaceStore(baseDirectory: tempDir),
            credentialStore: MemoryKeychain()
        )

        let dbPath = tempDir.appendingPathComponent("tour.sqlite").path
        let profile = ConnectionProfile(name: "Tour DB", kind: .sqlite, database: dbPath)
        model.saveProfile(profile, password: nil)
        let sqlite = SQLiteConnection(profile: profile)
        try await sqlite.connect(password: nil)
        _ = try await sqlite.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
        _ = try await sqlite.execute("INSERT INTO users (name, score) VALUES ('ada', 9.5), ('bob', 3.25)")
        try await sqlite.disconnect()

        let hosting = NSHostingView(
            rootView: ContentView()
                .environment(model)
                .frame(width: 1280, height: 820)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        try await pump(0.4)

        for _ in 0..<2 {
            model.toggleSidebar()
            try await pump()
            model.toggleAIPanel()
            try await pump()
            model.toggleResults()
            try await pump()
        }
        model.toggleFocusMode()
        try await pump()
        model.toggleFocusMode()
        try await pump()
        note("pane + mode toggles")

        for mode in SidebarMode.allCases {
            model.setSidebarMode(mode)
            try await pump()
        }
        note("sidebar modes")

        let t1 = model.newTab(title: "tour-1", sql: "SELECT 1;")
        let t2 = model.newTab(title: "tour-2", sql: "SELECT 2;")
        try await pump()
        model.closeTab(t1.id)
        try await pump()
        model.closeTab(t2.id)
        try await pump()
        let t3 = model.newTab(title: "tour-3", sql: "SELECT id, name FROM users;")
        try await pump()
        note("tabs")

        model.showingConnectionEditor = true
        try await pump(0.4)
        model.showingConnectionEditor = false
        try await pump(0.3)
        model.showingSaveQuerySheet = true
        try await pump(0.4)
        model.showingSaveQuerySheet = false
        try await pump(0.3)
        model.showingSettingsSearch = true
        try await pump(0.4)
        model.showingSettingsSearch = false
        try await pump(0.3)
        note("sheets")

        model.selectedTabID = t3.id
        model.connect(profile)
        model.setSelectedTabConnection(profile.id)
        var waited = 0.0
        while model.status(for: profile.id) != .connected, waited < 5 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 0.02
        }
        guard model.status(for: profile.id) == .connected else {
            throw TourError.step("connection did not complete")
        }
        model.run(t3.id)
        waited = 0
        while model.results[t3.id]?.first?.status != .complete, waited < 10 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 0.02
        }
        guard let result = model.results[t3.id]?.first, result.status == .complete else {
            throw TourError.step("query did not complete")
        }
        guard result.model.rows.count == 2 else {
            throw TourError.step("unexpected row count \(result.model.rows.count)")
        }
        note("query run")

        model.toggleEditorAIComposer()
        try await pump()
        model.editorAIPrompt = "tour prompt"
        try await pump()
        model.toggleEditorAIComposer()
        try await pump()
        note("ai composer")

        guard window.isVisible else {
            throw TourError.step("window is not visible after the tour")
        }
        guard !model.document.openTabs.isEmpty else {
            throw TourError.step("no tabs open after the tour")
        }
        guard model.selectedTabID != nil, model.selectedTabConnectionID != nil else {
            throw TourError.step("active tab lost its connection binding after the tour")
        }
        try await sqlite.disconnect()
    }

    @MainActor
    static func pump(_ seconds: Double = 0.2) async throws {
        try await Task.sleep(for: .milliseconds(UInt64(seconds * 1000)))
        pumpSync()
    }

    nonisolated static func pumpSync() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    @MainActor
    static func note(_ message: String) {
        fputs("TOUR step: \(message)\n", stderr)
    }
}

enum TourError: Error {
    case step(String)
}

extension TourError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .step(let message): message
        }
    }
}

final class MemoryKeychain: CredentialStore {
    func setPassword(_ password: String, for profileID: UUID) throws {}
    func password(for profileID: UUID) throws -> String? { nil }
    func deletePassword(for profileID: UUID) throws {}
}
