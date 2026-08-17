import AppKit
import SwiftUI
import SQLCore

struct AIComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool
    var onSubmit: () -> Void
    var mentionActive: Bool
    var mentionCount: Int
    @Binding var mentionIndex: Int
    @Binding var caret: Int?
    var validatedMentionKeys: Set<String>
    var onPickMention: () -> Void
    var autoFocus: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, mentionIndex: $mentionIndex, caret: $caret, onSubmit: onSubmit, onPickMention: onPickMention)
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
        tv.onMentionKey = { [weak coordinator = context.coordinator] event in
            coordinator?.handleMentionKey(event) ?? false
        }
        tv.isRichText = true
        tv.allowsUndo = true
        tv.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        tv.textColor = .labelColor
        tv.insertionPointColor = .labelColor
        tv.typingAttributes = Coordinator.plainAttributes
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.minSize = NSSize(width: 0, height: 22)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 88)
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
        context.coordinator.onPickMention = onPickMention
        context.coordinator.mentionActive = mentionActive
        context.coordinator.mentionCount = mentionCount
        context.coordinator.validatedMentionKeys = validatedMentionKeys
        context.coordinator.placeholder = placeholder
        guard let tv = scroll.documentView as? ComposerNSTextView else { return }
        tv.isEditable = isEnabled
        tv.isSelectable = true
        if tv.string != text {
            tv.string = text
            if let caret {
                let loc = min(max(caret, 0), (text as NSString).length)
                tv.setSelectedRange(NSRange(location: loc, length: 0))
                context.coordinator.caret.wrappedValue = nil
            } else {
                tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            }
        }
        context.coordinator.applyHighlights()
        if autoFocus, isEnabled, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
            }
        }
        context.coordinator.updatePlaceholder()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var mentionIndex: Binding<Int>
        var caret: Binding<Int?>
        var onSubmit: () -> Void
        var onPickMention: () -> Void
        var mentionActive = false
        var mentionCount = 0
        var validatedMentionKeys: Set<String> = []
        var placeholder: String = ""
        weak var textView: ComposerNSTextView?
        var didFocus = false

        static let plainAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]

        init(
            text: Binding<String>,
            mentionIndex: Binding<Int>,
            caret: Binding<Int?>,
            onSubmit: @escaping () -> Void,
            onPickMention: @escaping () -> Void
        ) {
            self.text = text
            self.mentionIndex = mentionIndex
            self.caret = caret
            self.onSubmit = onSubmit
            self.onPickMention = onPickMention
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
            applyHighlights()
            updatePlaceholder()
        }

        func applyHighlights() {
            guard let storage = textView?.textStorage else { return }
            let ns = storage.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            storage.addAttributes(Self.plainAttributes, range: full)
            for token in AIMention.tokens(in: storage.string) {
                let matched = validatedMentionKeys.contains(token.raw.lowercased())
                    || validatedMentionKeys.contains(token.name.lowercased())
                guard matched else { continue }
                let range = NSRange(location: token.utf16Range.lowerBound, length: token.utf16Range.count)
                guard NSMaxRange(range) <= ns.length else { continue }
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.controlAccentColor,
                        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                    ],
                    range: range
                )
            }
        }

        func handleMentionKey(_ event: NSEvent) -> Bool {
            guard mentionActive else { return false }
            switch event.keyCode {
            case 126:
                mentionIndex.wrappedValue = max(mentionIndex.wrappedValue - 1, 0)
                return true
            case 125:
                mentionIndex.wrappedValue = min(mentionIndex.wrappedValue + 1, max(mentionCount - 1, 0))
                return true
            case 48:
                if mentionCount > 0 {
                    onPickMention()
                    return true
                }
                return false
            default:
                return false
            }
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
    nonisolated(unsafe) var onMentionKey: ((NSEvent) -> Bool)?
    nonisolated(unsafe) var showsPlaceholder = false
    nonisolated(unsafe) var placeholderString = ""

    override func keyDown(with event: NSEvent) {
        if onMentionKey?(event) == true {
            return
        }
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
