import SwiftUI
import UniformTypeIdentifiers

struct ListReorderDropDelegate: DropDelegate {
    let targetID: UUID?
    let draggingID: () -> UUID?
    let setDraggingID: (UUID?) -> Void
    let move: (UUID, UUID?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingID() != nil || info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = resolveDraggedID(info) else { return }
        if let targetID, dragged == targetID { return }
        move(dragged, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let dragged = resolveDraggedID(info) {
            if targetID == nil || dragged != targetID {
                move(dragged, targetID)
            }
        }
        setDraggingID(nil)
        return true
    }

    func dropExited(info: DropInfo) {}

    private func resolveDraggedID(_ info: DropInfo) -> UUID? {
        draggingID()
    }
}

struct DragSessionEndMonitor: NSViewRepresentable {
    var onEnd: @Sendable () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(onEnd: onEnd)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onEnd = onEnd
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: @unchecked Sendable {
        var onEnd: (@Sendable () -> Void)?
        private var monitor: Any?

        func install(onEnd: @escaping @Sendable () -> Void) {
            self.onEnd = onEnd
            teardown()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                let callback = self?.onEnd
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    callback?()
                }
                return event
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { teardown() }
    }
}
