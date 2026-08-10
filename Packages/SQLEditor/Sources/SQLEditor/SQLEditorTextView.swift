import AppKit

public final class SQLEditorTextView: NSTextView {
    public var onRun: ((String) -> Void)?
    public var onSaveQuery: ((String) -> Void)?

    public let gutterView = LineNumberGutterView(frame: .zero)

    public var textLeadingPad: CGFloat = 6
    public var textTrailingPad: CGFloat = 6
    public var textVerticalInset: CGFloat = 10

    private var highlightWorkItem: DispatchWorkItem?
    private var isApplyingHighlight = false
    private var gutterWidth: CGFloat = 28

    public init() {
        super.init(frame: .zero)
        setup()
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        font = Self.baseFont
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        textContainerInset = NSSize(width: 0, height: textVerticalInset)
        drawsBackground = false
        backgroundColor = .textBackgroundColor

        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = false
        textContainer?.lineFragmentPadding = 4
        textContainer?.containerSize = NSSize(width: max(bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)
        isAutomaticTextCompletionEnabled = false

        typingAttributes = Self.baseTypingAttributes(layoutManager: layoutManager)
        defaultParagraphStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle

        gutterView.textView = self
        addSubview(gutterView)
    }

    public static let lineHeightPadding: CGFloat = 4
    public static func baseTypingAttributes(layoutManager: NSLayoutManager?) -> [NSAttributedString.Key: Any] {
        let font = baseFont
        let lm = layoutManager ?? NSLayoutManager()
        let lineHeight = lm.defaultLineHeight(for: font) + lineHeightPadding
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
    }

    public override var textContainerOrigin: NSPoint {
        NSPoint(x: gutterWidth + textLeadingPad, y: textContainerInset.height)
    }

    public func applyGutterLayout(viewWidth: CGFloat) {
        gutterView.invalidate()
        let newGutterW = max(gutterView.preferredWidth, 28)
        let gutterChanged = abs(newGutterW - gutterWidth) > 0.5
        gutterWidth = newGutterW
        let textWidth = max(
            viewWidth - gutterWidth - textLeadingPad - textTrailingPad,
            50
        )
        if let tc = textContainer {
            tc.widthTracksTextView = false
            tc.containerSize = NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        textContainerInset = NSSize(width: 0, height: textVerticalInset)
        if gutterChanged {
            invalidateTextContainerOrigin()
        }
        layoutGutter()
    }

    public func layoutGutter() {
        let height = max(bounds.height, 1)
        gutterView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: height)
        gutterView.needsDisplay = true
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(bounds.width) > 0.5 {
            applyGutterLayout(viewWidth: bounds.width)
        } else {
            layoutGutter()
        }
        gutterView.invalidate()
    }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        gutterView.invalidate()
    }

    public override var font: NSFont? {
        get { super.font }
        set {
            super.font = newValue
            typingAttributes = Self.baseTypingAttributes(layoutManager: layoutManager)
            defaultParagraphStyle = typingAttributes[.paragraphStyle] as? NSParagraphStyle
            gutterView.invalidate()
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let runItem = NSMenuItem(title: "Run", action: #selector(contextRun(_:)), keyEquivalent: "")
        runItem.target = self
        menu.addItem(runItem)
        let saveItem = NSMenuItem(title: "Save Query…", action: #selector(contextSaveQuery(_:)), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func contextRun(_ sender: Any?) {
        run()
    }

    @objc private func contextSaveQuery(_ sender: Any?) {
        let sql = activeSQLSnippet()
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        onSaveQuery?(sql)
    }

    public func activeSQLSnippet() -> String {
        Self.sqlToRun(fullText: string, selectedRange: selectedRange())
    }

    public static func sqlToRun(fullText: String, selectedRange: NSRange) -> String {
        guard selectedRange.length > 0,
              selectedRange.location != NSNotFound else {
            return fullText
        }
        let ns = fullText as NSString
        let end = ns.length
        guard selectedRange.location >= 0,
              selectedRange.location <= end,
              selectedRange.location + selectedRange.length <= end else {
            return fullText
        }
        let selected = ns.substring(with: selectedRange)
        if selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fullText
        }
        return selected
    }

    // MARK: - Highlighting

    public func highlightNow() {
        guard let textStorage, !isApplyingHighlight else { return }
        isApplyingHighlight = true
        defer { isApplyingHighlight = false }

        let text = string
        if !text.isEmpty {
            let tokens = SQLLexer().tokenize(text)
            let baseAttributes = Self.baseTypingAttributes(layoutManager: layoutManager)

            textStorage.beginEditing()
            textStorage.setAttributes(baseAttributes, range: NSRange(location: 0, length: textStorage.length))

            for token in tokens {
                guard token.location + token.length <= textStorage.length else { continue }
                let range = NSRange(location: token.location, length: token.length)
                guard let color = Self.color(for: SyntaxRoleMapping.role(for: token.kind)) else { continue }
                textStorage.addAttribute(.foregroundColor, value: color, range: range)
            }
            textStorage.endEditing()
        }
        gutterView.invalidate()
    }

    public func scheduleHighlight(delay: Double = 0.15) {
        highlightWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.highlightNow()
            }
        }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - Colors

    private static func color(for role: SyntaxRole) -> NSColor? {
        switch role {
        case .keyword: .systemPurple
        case .string: .systemRed
        case .number: .systemBlue
        case .comment: .secondaryLabelColor
        case .parameter: .systemOrange
        case .identifier: .labelColor
        case .other: .labelColor
        }
    }

    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    // MARK: - Run

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "\r" {
            run()
            return
        }
        super.keyDown(with: event)
    }

    public func run() {
        let sql = activeSQLSnippet()
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onRun?(sql)
    }
}
