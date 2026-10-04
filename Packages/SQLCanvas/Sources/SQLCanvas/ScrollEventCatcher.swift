import AppKit
import SwiftUI

struct ScrollEventCatcher: NSViewRepresentable {
    var isEnabled: Bool = true
    var onScroll: (CGSize) -> Void

    func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.isEnabled = isEnabled
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCatcherView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onScroll = onScroll
    }

    final class ScrollCatcherView: NSView {
        var isEnabled = true
        var onScroll: ((CGSize) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
                    guard let self, event.window === self.window else { return event }
                    guard self.isEnabled else { return event }
                    let location = self.convert(event.locationInWindow, from: nil)
                    guard self.bounds.contains(location) else { return event }
                    DispatchQueue.main.async {
                        self.onScroll?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                    }
                    return nil
                })
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
