import AppKit
import SwiftUI

@MainActor
final class WelcomeWindow {
    static let shared = WelcomeWindow()

    private var window: NSWindow?

    func show(model: WorkspaceModel) {
        guard window == nil else { return }
        let content = WelcomeView()
            .environment(model)
            .frame(width: 880, height: 560)

        let panel = WelcomePanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: content)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class WelcomePanel: NSWindow {
    override var canBecomeKey: Bool { true }
}
