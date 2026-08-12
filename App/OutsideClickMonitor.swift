import AppKit
import SwiftUI

struct OutsideClickMonitor: NSViewRepresentable {
    var enabled: Bool
    var onOutside: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.enabled = enabled
        view.onOutside = onOutside
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.enabled = enabled
        view.onOutside = onOutside
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.teardown()
    }

    final class MonitorView: NSView {
        var enabled = false
        var onOutside: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                install()
            } else {
                teardown()
            }
        }

        func install() {
            teardown()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            guard enabled, let window else { return }
            if isMenuEvent(event) { return }
            if event.window !== window {
                onOutside?()
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            if !bounds.contains(point) {
                onOutside?()
            }
        }

        private func isMenuEvent(_ event: NSEvent) -> Bool {
            guard let eventWindow = event.window else { return false }
            let name = String(describing: type(of: eventWindow))
            if name.contains("Menu") { return true }
            if eventWindow.level > .normal { return true }
            return false
        }

        deinit {
            teardown()
        }
    }
}
