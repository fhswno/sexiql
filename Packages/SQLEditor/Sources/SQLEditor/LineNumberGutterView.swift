import AppKit

public struct LineNumberSlot: Equatable, Sendable {
    public let lineNumber: Int
    public let fragmentInText: CGRect

    public var midY: CGFloat { fragmentInText.midY }
}

public final class LineNumberGutterView: NSView {
    public weak var textView: NSTextView?

    public var edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    public var minimumDigits = 2

    public var onWidthChange: ((CGFloat) -> Void)?

    private var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private var numberColumnWidth: CGFloat = 12
    private var maxDigitCount = 2

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public var preferredWidth: CGFloat {
        ceil(numberColumnWidth + edgeInsets.left + edgeInsets.right)
    }

    public func invalidate() {
        updateWidthIfNeeded()
        needsDisplay = true
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func updateWidthIfNeeded() {
        guard let textView else { return }
        font = textView.font ?? font
        let lines = Self.hardLineCount(textView.string)
        let digits = max(minimumDigits, String(lines).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let width = ceil(sample.size(withAttributes: [.font: font]).width)
        let changed = digits != maxDigitCount || abs(width - numberColumnWidth) > 0.5
        maxDigitCount = digits
        numberColumnWidth = width
        if changed {
            onWidthChange?(preferredWidth)
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let textView else { return }
        font = textView.font ?? font

        let selectedLine = Self.hardLineIndex(at: textView.selectedRange().location, in: textView.string)
        let slots = Self.lineSlots(for: textView)
        let visible = textView.visibleRect.insetBy(dx: 0, dy: -font.pointSize)

        for slot in slots {
            guard visible.intersects(slot.fragmentInText) || textView.string.isEmpty else { continue }
            drawNumber(
                slot.lineNumber,
                midY: slot.midY,
                emphasize: slot.lineNumber - 1 == selectedLine
            )
        }
    }

    private func drawNumber(_ number: Int, midY: CGFloat, emphasize: Bool) {
        let color: NSColor = emphasize ? .secondaryLabelColor : .tertiaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let label = "\(number)" as NSString
        let size = label.size(withAttributes: attributes)
        let x = bounds.maxX - edgeInsets.right - size.width
        let y = midY - size.height / 2
        label.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    // MARK: - Shared layout

    public static func lineSlots(for textView: NSTextView) -> [LineNumberSlot] {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return [] }
        let font = textView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        return lineSlots(
            string: textView.string,
            layoutManager: layoutManager,
            textContainer: textContainer,
            textOrigin: textView.textContainerOrigin,
            font: font
        )
    }

    public static func lineSlots(
        string: String,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textOrigin: NSPoint,
        font: NSFont
    ) -> [LineNumberSlot] {
        layoutManager.ensureLayout(for: textContainer)
        var slots: [LineNumberSlot] = []

        if string.isEmpty || layoutManager.numberOfGlyphs == 0 {
            let extra = layoutManager.extraLineFragmentRect
            let lineHeight = extra.height > 0.5
                ? extra.height
                : max(layoutManager.defaultLineHeight(for: font), 1)
            let frag = CGRect(
                x: textOrigin.x,
                y: textOrigin.y + (extra.height > 0.5 ? extra.minY : 0),
                width: max(textContainer.containerSize.width, 1),
                height: lineHeight
            )
            slots.append(LineNumberSlot(lineNumber: 1, fragmentInText: frag))
            return slots
        }

        var glyphIndex = 0
        let glyphCount = layoutManager.numberOfGlyphs
        var lastHardLine = -1

        while glyphIndex < glyphCount {
            var lineGlyphRange = NSRange()
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let hardLine = hardLineIndex(at: charIndex, in: string)

            if hardLine != lastHardLine {
                lastHardLine = hardLine
                let inText = CGRect(
                    x: fragmentRect.minX + textOrigin.x,
                    y: fragmentRect.minY + textOrigin.y,
                    width: fragmentRect.width,
                    height: fragmentRect.height
                )
                slots.append(LineNumberSlot(lineNumber: hardLine + 1, fragmentInText: inText))
            }

            let next = NSMaxRange(lineGlyphRange)
            if next <= glyphIndex { break }
            glyphIndex = next
        }

        if shouldDrawExtraLineNumber(for: string),
           layoutManager.extraLineFragmentTextContainer != nil {
            let lineNumber = hardLineCount(string)
            if lastHardLine < lineNumber - 1 {
                let extra = layoutManager.extraLineFragmentRect
                let inText = CGRect(
                    x: extra.minX + textOrigin.x,
                    y: extra.minY + textOrigin.y,
                    width: max(extra.width, 1),
                    height: max(extra.height, layoutManager.defaultLineHeight(for: font))
                )
                slots.append(LineNumberSlot(lineNumber: lineNumber, fragmentInText: inText))
            }
        }

        return slots
    }

    public static func caretLineMidY(for textView: NSTextView) -> CGFloat? {
        let slots = lineSlots(for: textView)
        let line = hardLineIndex(at: textView.selectedRange().location, in: textView.string)
        return slots.first(where: { $0.lineNumber - 1 == line })?.midY
    }

    // MARK: - Line indexing

    public static func shouldDrawExtraLineNumber(for string: String) -> Bool {
        string.isEmpty || string.last == "\n"
    }

    public static func hardLineCount(_ string: String) -> Int {
        if string.isEmpty { return 1 }
        var count = 1
        for ch in string where ch == "\n" { count += 1 }
        return count
    }

    public static func hardLineIndex(at utf16Offset: Int, in string: String) -> Int {
        if string.isEmpty || utf16Offset <= 0 { return 0 }
        let ns = string as NSString
        let end = min(max(utf16Offset, 0), ns.length)
        let prefix = ns.substring(to: end)
        var line = 0
        for ch in prefix where ch == "\n" { line += 1 }
        return line
    }
}
