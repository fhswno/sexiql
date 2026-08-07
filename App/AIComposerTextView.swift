import AppKit
import SwiftUI

struct AIComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let tv = ComposerNSTextView()
        tv.delegate = context.coordinator
        tv.onSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.onSubmit()
        }
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        tv.textColor = .labelColor
        tv.insertionPointColor = .labelColor
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text
        tv.setAccessibilityLabel(placeholder)
        context.coordinator.textView = tv
        context.coordinator.placeholder = placeholder

        scroll.documentView = tv
        context.coordinator.updatePlaceholder()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.placeholder = placeholder
        guard let tv = scroll.documentView as? ComposerNSTextView else { return }
        tv.isEditable = isEnabled
        tv.isSelectable = true
        if tv.string != text {
            let selected = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = selected
        }
        context.coordinator.updatePlaceholder()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var placeholder: String = ""
        weak var textView: ComposerNSTextView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
            updatePlaceholder()
        }

        func updatePlaceholder() {
            guard let tv = textView else { return }
            tv.showsPlaceholder = text.wrappedValue.isEmpty
            tv.placeholderString = placeholder
        }
    }
}

final class ComposerNSTextView: NSTextView {
    nonisolated(unsafe) var onSubmit: (() -> Void)?
    nonisolated(unsafe) var showsPlaceholder = false
    nonisolated(unsafe) var placeholderString = ""

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn {
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
                return
            }
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder, !placeholderString.isEmpty, string.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let inset = textContainerInset
        let rect = bounds.insetBy(dx: inset.width, dy: inset.height)
        placeholderString.draw(in: rect, withAttributes: attrs)
    }
}
