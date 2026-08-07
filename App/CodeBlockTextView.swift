import AppKit
import SwiftUI

struct CodeBlockTextView: NSViewRepresentable {
    let code: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.contentView = TopLeadingClipView(frame: scroll.contentView.frame)
        scroll.contentView.drawsBackground = false

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = .labelColor
        tv.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        tv.textContainerInset = NSSize(width: 10, height: 8)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainer?.lineFragmentPadding = 0
        tv.alignment = .natural
        tv.string = code

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.relayout(scroll: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != code {
            tv.string = code
        }
        context.coordinator.relayout(scroll: scroll)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var textView: NSTextView?

        func relayout(scroll: NSScrollView) {
            guard let tv = scroll.documentView as? NSTextView,
                  let container = tv.textContainer,
                  let layout = tv.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            let inset = tv.textContainerInset
            let contentW = max(scroll.contentSize.width, 1)
            let w = max(used.origin.x + used.width + inset.width * 2 + 2, contentW)
            let h = max(used.origin.y + used.height + inset.height * 2 + 2, 1)
            tv.frame = NSRect(x: 0, y: 0, width: w, height: h)
        }
    }
}

final class TopLeadingClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let docFrame = doc.frame

        if rect.width > docFrame.width {
            rect.origin.x = docFrame.minX
        }
        if rect.height > docFrame.height {
            if doc.isFlipped {
                rect.origin.y = docFrame.minY
            } else {
                rect.origin.y = docFrame.maxY - rect.height
            }
        }
        return rect
    }
}
