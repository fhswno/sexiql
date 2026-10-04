import AppKit
import SwiftUI

@MainActor
final class DropdownPanel: NSPanel, NSWindowDelegate {
    private let onDismiss: () -> Void

    init(anchorScreenRect: NSRect, width: CGFloat, content: NSView, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: 10)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        contentView = content
        delegate = self

        let contentSize = content.fittingSize
        let panelSize = NSSize(width: max(width, contentSize.width), height: max(10, contentSize.height))
        let origin = NSPoint(
            x: anchorScreenRect.maxX - panelSize.width,
            y: anchorScreenRect.minY - panelSize.height - 6
        )
        setFrame(NSRect(origin: origin, size: panelSize), display: true)
        makeKeyAndOrderFront(nil)
    }

    override var canBecomeKey: Bool { true }

    func dismiss() {
        guard delegate != nil else { return }
        delegate = nil
        onDismiss()
        orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            dismiss()
        }
    }
}

struct PillAnchorView: NSViewRepresentable {
    final class AnchorNSView: NSView {
        var onUpdate: ((NSWindow, NSRect) -> Void)?

        override func viewDidMoveToWindow() {
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        private func report() {
            guard let window, bounds != .zero else { return }
            let windowRect = convert(bounds, to: nil)
            onUpdate?(window, window.convertToScreen(windowRect))
        }
    }

    var onUpdate: (NSWindow, NSRect) -> Void

    func makeNSView(context: Context) -> AnchorNSView {
        let view = AnchorNSView()
        view.onUpdate = onUpdate
        return view
    }

    func updateNSView(_ nsView: AnchorNSView, context: Context) {
        nsView.onUpdate = onUpdate
    }
}
