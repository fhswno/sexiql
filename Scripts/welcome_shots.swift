import AppKit
import SwiftUI
import SQLCore
import SQLDrivers
import SQLGrid
@testable import SexiQLView

@main
struct WelcomeShots {
    @MainActor
    static func main() async throws {
        do {
            try await run()
        } catch {
            fputs("WELCOME SHOTS FAILED: \(error)\n", stderr)
            exit(1)
        }
        fputs("WELCOME SHOTS DONE\n", stderr)
        exit(0)
    }

    @MainActor
    static func run() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        copyIconsForBundleLookup()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WelcomeShots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: WorkspaceModel.welcomeSeenDefaultsKey)

        let model = WorkspaceModel(
            store: WorkspaceStore(baseDirectory: tempDir),
            credentialStore: MemoryKeychain()
        )
        guard model.showWelcome else {
            throw ShotError.step("welcome was not armed — UserDefaults flag set?")
        }

        let hosting = NSHostingView(
            rootView: WelcomeRoot(model: model)
                .frame(width: 1280, height: 820)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.contentView = hosting
        mainWindow.makeKeyAndOrderFront(nil)

        // ContentView.onAppear presents the dedicated WelcomeWindow splash panel.
        try await pause(1.0)

        guard let splash = splashPanel(excluding: mainWindow) else {
            throw ShotError.step("splash window did not appear")
        }
        guard let splashContent = splash.contentView else {
            throw ShotError.step("splash window has no contentView")
        }
        try snap(splashContent, "1-welcome")

        model.dismissWelcome()
        try await pause(0.8)
        guard splashPanel(excluding: mainWindow) == nil else {
            throw ShotError.step("splash window did not close after dismissal")
        }
        try snap(hosting, "2-dismissed")
    }

    @MainActor
    private static func splashPanel(excluding main: NSWindow) -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && window !== main && !window.styleMask.contains(.titled)
        }
    }

    /// WelcomeView loads the app icon via Bundle.main; for a CLI harness that is
    /// the directory containing the executable. Copy the icon PNGs there so the
    /// brand block renders with the real logo.
    private static func copyIconsForBundleLookup() {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assets = repo.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
        let destination = URL(fileURLWithPath: Bundle.main.bundlePath, isDirectory: true)
        let pairs = [
            ("AppIcon.png", "AppIcon-dark.png"),
            ("AppIcon-light.png", "AppIcon-light.png"),
        ]
        for (sourceName, destinationName) in pairs {
            let from = assets.appendingPathComponent(sourceName)
            let to = destination.appendingPathComponent(destinationName)
            try? FileManager.default.removeItem(at: to)
            try? FileManager.default.copyItem(at: from, to: to)
        }
    }

    @MainActor
    private static func snap(_ view: NSView, _ name: String) throws {
        pumpSync()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ShotError.step("bitmap rep unavailable for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw ShotError.step("png encoding failed for \(name)")
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/welcome-shot-\(name).png"))
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

enum ShotError: Error {
    case step(String)
}

struct WelcomeRoot: View {
    @State var model: WorkspaceModel

    var body: some View {
        ContentView()
            .environment(model)
            .preferredColorScheme(.dark)
    }
}

extension ShotError: LocalizedError {
    var errorDescription: String? { switch self { case .step(let message): message } }
}

final class MemoryKeychain: CredentialStore {
    func setPassword(_ password: String, for profileID: UUID) throws {}
    func password(for profileID: UUID) throws -> String? { nil }
    func deletePassword(for profileID: UUID) throws {}
}
