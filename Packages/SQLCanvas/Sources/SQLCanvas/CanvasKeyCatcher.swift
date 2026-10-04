import AppKit
import SwiftUI

struct CanvasKeyCatcher: NSViewRepresentable {
    var onKeyEvent: (_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Bool

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onKeyEvent = onKeyEvent
    }

    final class KeyCatcherView: NSView {
        var onKeyEvent: ((_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                    guard let self, event.window === self.window else { return event }
                    if window?.firstResponder is NSTextView { return event }
                    if let onKeyEvent, onKeyEvent(event.keyCode, event.modifierFlags) {
                        return nil
                    }
                    return event
                })
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
