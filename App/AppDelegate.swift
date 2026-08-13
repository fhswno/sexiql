import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    var workspace: WorkspaceModel?
    private var appearanceObservation: NSKeyValueObservation?
    private var launchFinished = false
    private var hasOpenedMainWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        SparkleUpdater.shared.configureIfEnabled()
        AppIconAppearance.apply(for: .system)

        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor in
                NotificationCenter.default.post(name: .sexiqlSystemAppearanceDidChange, object: nil)
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        DispatchQueue.main.async { [weak self] in
            self?.launchFinished = true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace?.saveWorkspace()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        launchFinished && hasOpenedMainWindow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        flag == false
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.styleMask.contains(.titled), window.frame.width >= 800 {
            hasOpenedMainWindow = true
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension Notification.Name {
    static let sexiqlSystemAppearanceDidChange = Notification.Name("sexiqlSystemAppearanceDidChange")
}
