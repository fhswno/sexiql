import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SparkleUpdater.shared.configureIfEnabled()
        // Default until WorkspaceModel applies the saved preference.
        AppIconAppearance.apply(for: .system)

        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor in
                // Only follow the system Dock icon when the user chose System.
                NotificationCenter.default.post(name: .sexiqlSystemAppearanceDidChange, object: nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let sexiqlSystemAppearanceDidChange = Notification.Name("sexiqlSystemAppearanceDidChange")
}
