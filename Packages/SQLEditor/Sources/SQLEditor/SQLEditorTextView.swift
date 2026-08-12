import AppKit

public final class SQLEditorTextView: NSTextView {
    public var onRun: ((String) -> Void)?
    public var onSaveQuery: ((String) -> Void)?
    public var completionCatalog: (() -> SQLCompletionCatalog)?
    public var onNeedColumns: ((String) -> Void)?

    public let gutterView = LineNumberGutterView(frame: .zero)

    public var textLeadingPad: CGFloat = 6
    public var textTrailingPad: CGFloat = 6
    public var textVerticalInset: CGFloat = 10

    private var highlightWorkItem: DispatchWorkItem?
    private var completionWorkItem: DispatchWorkItem?
    private var isApplyingHighlight = false
    private var gutterWidth: CGFloat = 28
    private let completion = SQLCompletionWindow()
    private var completionReplaceRange = NSRange(location: 0, length: 0)
    private var suppressCompletion = false

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
        completion.onAccept = { [weak self] item in
            self?.insertCompletion(item)
        }
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

    // MARK: - Run / Comment

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "\r" {
            completion.hide()
            run()
            return
        }
        if flags == .command, event.charactersIgnoringModifiers == "/" {
            completion.hide()
            toggleLineComment()
            return
        }
        if flags == .control, event.charactersIgnoringModifiers == " " {
            refreshCompletion(force: true)
            return
        }
        if completion.isVisible {
            switch event.keyCode {
            case 125:
                completion.moveSelection(1)
                return
            case 126:
                completion.moveSelection(-1)
                return
            case 36, 48:
                if completion.accept() { return }
            case 53:
                completion.hide()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
        scheduleCompletion()
    }

    public override func didChangeText() {
        super.didChangeText()
        scheduleCompletion()
    }

    public override func resignFirstResponder() -> Bool {
        completion.hide()
        return super.resignFirstResponder()
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            completion.hide()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "/" {
            toggleLineComment()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func scheduleCompletion() {
        if suppressCompletion { return }
        completionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshCompletion(force: false)
        }
        completionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    public func refreshCompletion(force: Bool) {
        let catalog = completionCatalog?() ?? .keywordsOnly
        let cursor = selectedRange().location
        let result = SQLCompletionEngine().suggestions(
            sql: string,
            cursor: cursor,
            catalog: catalog,
            force: force
        )
        completionReplaceRange = result.replaceRange
        if let qualifier = result.pendingQualifier {
            onNeedColumns?(qualifier)
        }
        if result.items.isEmpty {
            completion.hide()
        } else {
            completion.show(result.items, from: self)
        }
    }

    private func insertCompletion(_ item: SQLCompletionItem) {
        let range = completionReplaceRange
        let end = (string as NSString).length
        guard range.location >= 0, range.location + range.length <= end else { return }
        suppressCompletion = true
        if shouldChangeText(in: range, replacementString: item.insertText) {
            replaceCharacters(in: range, with: item.insertText)
            didChangeText()
        }
        suppressCompletion = false
        let loc = range.location + (item.insertText as NSString).length
        setSelectedRange(NSRange(location: loc, length: 0))
        scheduleHighlight(delay: 0)
        completion.hide()
    }

    public func run() {
        let sql = activeSQLSnippet()
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onRun?(sql)
    }

    public func toggleLineComment() {
        guard let textStorage else { return }
        let full = textStorage.string as NSString
        guard full.length > 0 || selectedRange().length == 0 else { return }

        let sel = selectedRange()
        var block = full.paragraphRange(for: NSRange(location: min(sel.location, full.length), length: 0))
        if sel.length > 0 {
            let endLoc = min(sel.location + sel.length, full.length)
            var endRange = NSRange(location: endLoc, length: 0)
            if endLoc > sel.location, endLoc < full.length {
                let prev = full.character(at: endLoc - 1)
                if prev == 10 || prev == 13 {
                    endRange = NSRange(location: endLoc - 1, length: 0)
                }
            }
            let endPara = full.paragraphRange(for: endRange)
            let start = full.paragraphRange(for: NSRange(location: sel.location, length: 0)).location
            let end = endPara.location + endPara.length
            block = NSRange(location: start, length: max(0, end - start))
        }

        if full.length == 0 {
            let insertion = "-- "
            if shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: insertion) {
                textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: insertion)
                didChangeText()
                setSelectedRange(NSRange(location: insertion.utf16.count, length: 0))
                scheduleHighlight(delay: 0)
            }
            return
        }

        guard block.location + block.length <= full.length else { return }

        var lineRanges: [NSRange] = []
        full.enumerateSubstrings(in: block, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lineRanges.append(range)
        }
        if lineRanges.isEmpty {
            lineRanges = [block]
        }

        let contentLines = lineRanges.filter { range in
            let line = full.substring(with: range)
            return !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let targets = contentLines.isEmpty ? lineRanges : contentLines

        let allCommented = targets.allSatisfy { range in
            let line = full.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("--")
        }

        var replacements: [(NSRange, String)] = []
        for range in targets {
            let line = full.substring(with: range) as NSString
            if allCommented {
                var i = 0
                while i < line.length {
                    let ch = line.character(at: i)
                    if ch == 32 || ch == 9 { i += 1; continue }
                    break
                }
                guard i < line.length, line.character(at: i) == 45 else { continue }
                var stripLen = 1
                if i + 1 < line.length, line.character(at: i + 1) == 45 {
                    stripLen = 2
                    if i + 2 < line.length, line.character(at: i + 2) == 32 {
                        stripLen = 3
                    }
                } else {
                    continue
                }
                let stripRange = NSRange(location: range.location + i, length: stripLen)
                replacements.append((stripRange, ""))
            } else {
                var i = 0
                while i < line.length {
                    let ch = line.character(at: i)
                    if ch == 32 || ch == 9 { i += 1; continue }
                    break
                }
                let insertAt = NSRange(location: range.location + i, length: 0)
                replacements.append((insertAt, "-- "))
            }
        }

        guard !replacements.isEmpty else { return }

        undoManager?.beginUndoGrouping()
        textStorage.beginEditing()
        var delta = 0
        let ordered = replacements.sorted { $0.0.location > $1.0.location }
        for (range, text) in ordered {
            if shouldChangeText(in: range, replacementString: text) {
                textStorage.replaceCharacters(in: range, with: text)
                delta += (text as NSString).length - range.length
            }
        }
        textStorage.endEditing()
        didChangeText()
        undoManager?.endUndoGrouping()

        let newLocation = block.location
        let newLength = max(0, block.length + delta)
        let maxLen = textStorage.length
        let clamped = NSRange(
            location: min(newLocation, maxLen),
            length: min(newLength, max(0, maxLen - min(newLocation, maxLen)))
        )
        setSelectedRange(clamped)
        scheduleHighlight(delay: 0)
    }
}
