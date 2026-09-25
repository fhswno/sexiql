import AppKit
import SwiftUI
import SQLCore
import SQLDrivers
import SQLGrid
@testable import SexiQLView

@main
struct SettingsProbe {
    @MainActor
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("SETTINGS PROBE FAILED: \(error)\n", stderr)
            exit(1)
        }
        fputs("SETTINGS PROBE DONE\n", stderr)
        exit(0)
    }

    @MainActor
    static func run() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: WorkspaceModel.welcomeSeenDefaultsKey)

        let model = WorkspaceModel(
            store: WorkspaceStore(baseDirectory: tempDir),
            credentialStore: MemoryKeychain()
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(
            rootView: AnyView(
                SettingsChrome(model: model, preferredScheme: schemeFor(model.appearance))
                    .frame(width: 640, height: 640)
            )
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)

        try await pause(0.8)
        try snap(hosting, "1-initial")

        model.appearance = .light
        refreshRoot(hosting, model: model)
        try await pause(0.8)
        try snap(hosting, "2-light")

        model.appearance = .system
        refreshRoot(hosting, model: model)
        try await pause(0.8)
        try snap(hosting, "3-system")

        model.appearance = .dark
        refreshRoot(hosting, model: model)
        try await pause(0.8)
        try snap(hosting, "4-dark")
    }

    @MainActor
    private static func schemeFor(_ mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    @MainActor
    private static func refreshRoot(_ hosting: NSHostingView<AnyView>, model: WorkspaceModel) {
        hosting.rootView = AnyView(
            SettingsChrome(model: model, preferredScheme: schemeFor(model.appearance))
                .frame(width: 640, height: 640)
        )
    }

    @MainActor
    private static func snap(_ view: NSView, _ name: String) throws {
        pumpSync()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ProbeError.step("bitmap rep unavailable for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw ProbeError.step("png encoding failed for \(name)")
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/settings-shot-\(name).png"))
        fputs("shot: \(name)\n", stderr)
    }

    @MainActor
    private static func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(UInt64(seconds * 1000)))
        pumpSync()
    }

    nonisolated private static func pumpSync() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}

enum ProbeError: Error {
    case step(String)
}

extension ProbeError: LocalizedError {
    var errorDescription: String? { switch self { case .step(let message): message } }
}

final class MemoryKeychain: CredentialStore {
    func setPassword(_ password: String, for profileID: UUID) throws {}
    func password(for profileID: UUID) throws -> String? { nil }
    func deletePassword(for profileID: UUID) throws {}
}
