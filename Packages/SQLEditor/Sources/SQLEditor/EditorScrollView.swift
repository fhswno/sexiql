import AppKit

public final class EditorScrollView: NSScrollView {
    public let editorTextView: SQLEditorTextView

    public var gutterView: LineNumberGutterView {
        editorTextView.gutterView
    }

    public init() {
        editorTextView = SQLEditorTextView()
        super.init(frame: .zero)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        hasVerticalRuler = false
        rulersVisible = false
        automaticallyAdjustsContentInsets = false
        contentInsets = .init()
        scrollerInsets = .init()

        editorTextView.minSize = .zero
        editorTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.autoresizingMask = [.width]
        editorTextView.drawsBackground = false

        documentView = editorTextView

        editorTextView.gutterView.onWidthChange = { [weak self] _ in
            self?.tileDocument()
        }

        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override func layout() {
        super.layout()
        tileDocument()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        tileDocument()
    }

    @objc private func contentBoundsChanged() {
        gutterView.needsDisplay = true
    }

    public func tileDocument() {
        let viewportW = max(contentSize.width, 1)
        let viewportH = max(contentSize.height, 1)

        editorTextView.gutterView.invalidate()
        editorTextView.applyGutterLayout(viewWidth: viewportW)

        if let lm = editorTextView.layoutManager, let tc = editorTextView.textContainer {
            lm.ensureLayout(for: tc)
            var used = lm.usedRect(for: tc)
            if lm.extraLineFragmentTextContainer != nil {
                used = used.union(lm.extraLineFragmentRect)
            }
            let insetY = editorTextView.textContainerInset.height
            let height = max(
                ceil(used.maxY + editorTextView.textContainerOrigin.y + insetY + 4),
                viewportH
            )
            editorTextView.setFrameSize(NSSize(width: viewportW, height: height))
            editorTextView.layoutGutter()
            editorTextView.gutterView.needsDisplay = true
        } else {
            editorTextView.setFrameSize(NSSize(width: viewportW, height: viewportH))
            editorTextView.layoutGutter()
        }
    }
}
