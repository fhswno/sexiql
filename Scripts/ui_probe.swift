import AppKit
import SwiftUI
import Vision
import SQLCore
import SQLDrivers
import SQLGrid
@testable import SexiQLView

@main
struct UIProbe {
    @MainActor
    static func main() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UIProbe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let model = WorkspaceModel(
            store: WorkspaceStore(baseDirectory: tempDir),
            credentialStore: MemoryKeychain()
        )

        let dbPath = tempDir.appendingPathComponent("probe.sqlite").path
        let profile = ConnectionProfile(name: "Probe DB", kind: .sqlite, database: dbPath)
        model.saveProfile(profile, password: nil)

        let sqlite = SQLiteConnection(profile: profile)
        do {
            try await sqlite.connect(password: nil)
            _ = try await sqlite.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
            _ = try await sqlite.execute("INSERT INTO users (name, score) VALUES ('ada', 9.5), ('bob', 3.25), ('carol', 7.0)")
            try await sqlite.disconnect()

            model.connect(profile)
            var waited = 0.0
            while model.status(for: profile.id) != .connected, waited < 5 {
                try await Task.sleep(for: .milliseconds(20))
                waited += 0.02
            }
            let tab = model.newTab(title: "probe", sql: "SELECT id, name, score FROM users;")
            model.setSelectedTabConnection(profile.id)
            model.selectedTabID = tab.id
            model.run(tab.id)
            waited = 0
            while model.results[tab.id]?.first?.status != .complete, waited < 5 {
                try await Task.sleep(for: .milliseconds(20))
                waited += 0.02
            }
            let result = model.results[tab.id]!.first!
            fputs("DIAG initial rows=\(result.model.rows.count) editable=\(String(describing: result.editableTable))\n", stderr)
            waited = 0
            while result.editableTable == nil && waited < 5 {
                try await Task.sleep(for: .milliseconds(20))
                waited += 0.02
            }
            fputs("DIAG editable=\(String(describing: result.editableTable))\n", stderr)

            model.handleCellEdit(tabID: tab.id, resultIndex: 0, row: 0, column: 1, newValue: .string("grace"))
            waited = 0
            while result.undoStack.isEmpty && waited < 5 {
                try await Task.sleep(for: .milliseconds(20))
                waited += 0.02
            }
            let editedName = try await sqlite.connect(password: nil) != nil ? "" : ""
            try await sqlite.connect(password: nil)
            let check = try await sqlite.execute("SELECT name FROM users WHERE id = 1")
            let dbName = check.rows.first?.values.first
            fputs("DIAG after edit: db name=\(String(describing: dbName)) grid=\(result.model[0, 1])\n", stderr)

            model.undoLastEdit(tabID: tab.id, resultIndex: 0)
            waited = 0
            while result.model[0, 1] != .string("ada") && waited < 5 {
                try await Task.sleep(for: .milliseconds(20))
                waited += 0.02
            }
            let check2 = try await sqlite.execute("SELECT name FROM users WHERE id = 1")
            fputs("DIAG after undo: db name=\(String(describing: check2.rows.first?.values.first))\n", stderr)

            model.saveCurrentQuery(name: "probe-saved")
            fputs("DIAG history=\(model.document.history.count) saved=\(model.document.savedQueries.count)\n", stderr)

            let csvPath = tempDir.appendingPathComponent("import.csv").path
            try "name,score\r\nzed,1.5\r\n".write(toFile: csvPath, atomically: true, encoding: .utf8)
            model.prepareImport(from: URL(fileURLWithPath: csvPath), profileID: profile.id)
            model.importSession?.targetTable = "users"
            await model.loadImportTargetColumns()
            if let session = model.importSession {
                waited = 0
                while session.tableColumns.isEmpty && waited < 5 {
                    try await Task.sleep(for: .milliseconds(20))
                    waited += 0.02
                }
                fputs("DIAG import columns=\(session.tableColumns) mapping=\(session.mapping)\n", stderr)
                await model.runImport()
                fputs("DIAG import inserted=\(session.inserted) failed=\(session.failed) err=\(String(describing: session.errorMessage))\n", stderr)
                let count = try await sqlite.execute("SELECT COUNT(*) FROM users")
                fputs("DIAG users after import=\(String(describing: count.rows.first?.values.first))\n", stderr)
            } else {
                fputs("DIAG import session nil\n", stderr)
            }

            render(model)
        } catch {
            fputs("setup error: \(error)\n", stderr)
        }
    }

    @MainActor
    static func render(_ model: WorkspaceModel) {
        let hosting = NSHostingView(
            rootView: ContentView()
                .environment(model)
                .frame(width: 1200, height: 800)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        for connection in model.document.connections {
            fputs("DIAG status[\(connection.name)] = \(model.status(for: connection.id))\n", stderr)
        }
        if let tabID = model.selectedTabID {
            for result in model.results[tabID] ?? [] {
                fputs("DIAG result status = \(result.status), rows = \(result.model.rows.count), columns = \(result.model.columns.count)\n", stderr)
            }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sexiql-ui.png")
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("no bitmap rep\n", stderr)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fputs("no png\n", stderr)
            return
        }
        try! data.write(to: url)
        fputs("captured \(url.path)\n", stderr)

        window.orderOut(nil)
        ocr(url)
    }

    static func ocr(_ url: URL) {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fputs("cannot load capture\n", stderr)
            return
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cg)
        do {
            try handler.perform([request])
        } catch {
            fputs("ocr error: \(error)\n", stderr)
            return  
        }
        let observations = (request.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
        print("== OCR (y=top-anchored fraction of image, x=left fraction) ==")
        for obs in observations {
            if let candidate = obs.topCandidates(1).first {
                let bb = obs.boundingBox
                let top = 1.0 - bb.maxY
                print(String(format: "top=%5.3f left=%5.3f  %@", top, bb.minX, candidate.string))
            }
        }
    }
}

final class MemoryKeychain: CredentialStore {
    func setPassword(_ password: String, for profileID: UUID) throws {}
    func password(for profileID: UUID) throws -> String? { nil }
    func deletePassword(for profileID: UUID) throws {}
}
