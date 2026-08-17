import AppKit

@MainActor
public final class SQLCompletionWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    public var onAccept: ((SQLCompletionItem) -> Void)?
    public var acceptOnSingleClick = false
    public var hidesWhenInactive: Bool {
        get { panel.hidesOnDeactivate }
        set { panel.hidesOnDeactivate = newValue }
    }

    private let panel: NSPanel
    private let tableView = NSTableView()
    private var items: [SQLCompletionItem] = []

    public override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none

        let scroll = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .lineBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor

        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = .controlBackgroundColor
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.action = #selector(singleClick)
        tableView.doubleAction = #selector(doubleClick)
        tableView.target = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 80
        tableView.addTableColumn(column)
        scroll.documentView = tableView
        panel.contentView = scroll
    }

    public var isVisible: Bool { panel.isVisible && !items.isEmpty }

    public var selectedItem: SQLCompletionItem? {
        let row = tableView.selectedRow
        guard items.indices.contains(row) else { return nil }
        return items[row]
    }

    public func show(
        _ items: [SQLCompletionItem],
        from textView: NSTextView,
        maxVisible: Int = 8,
        emptyMessage: String? = nil,
        belowView: Bool = false
    ) {
        if items.isEmpty, let emptyMessage, !emptyMessage.isEmpty {
            self.items = [
                SQLCompletionItem(kind: .table, label: emptyMessage, insertText: "", detail: nil),
            ]
        } else {
            self.items = items
        }
        tableView.reloadData()
        if !self.items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        guard !self.items.isEmpty, let window = textView.window else {
            hide()
            return
        }

        let rect = belowView ? fieldScreenRect(in: textView) : caretScreenRect(in: textView)
        let count = min(self.items.count, maxVisible)
        let height = CGFloat(count) * tableView.rowHeight + 6
        let width = preferredWidth(for: self.items)
        var frame = NSRect(x: rect.minX, y: rect.minY - height - 4, width: width, height: height)
        if let screen = window.screen ?? NSScreen.main {
            if frame.minY < screen.visibleFrame.minY {
                frame.origin.y = rect.maxY + 4
            }
            if frame.maxX > screen.visibleFrame.maxX {
                frame.origin.x = screen.visibleFrame.maxX - frame.width
            }
            if frame.minX < screen.visibleFrame.minX {
                frame.origin.x = screen.visibleFrame.minX + 4
            }
        }
        panel.setFrame(frame, display: true)
        if let column = tableView.tableColumns.first {
            column.width = max(80, width - 4)
        }
        tableView.sizeLastColumnToFit()
        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    public func hide() {
        items = []
        tableView.reloadData()
        panel.orderOut(nil)
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
    }

    public func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = min(max(tableView.selectedRow + delta, 0), items.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @discardableResult
    public func accept() -> Bool {
        guard let item = selectedItem, !item.insertText.isEmpty else { return false }
        onAccept?(item)
        hide()
        return true
    }

    @objc private func singleClick() {
        guard acceptOnSingleClick else { return }
        _ = accept()
    }

    @objc private func doubleClick() {
        _ = accept()
    }

    private func fieldScreenRect(in textView: NSTextView) -> NSRect {
        guard let window = textView.window else { return caretScreenRect(in: textView) }
        let host = textView.enclosingScrollView ?? textView
        var rect = window.convertToScreen(host.convert(host.bounds, to: nil))
        let caret = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
        if rect.insetBy(dx: -8, dy: -40).contains(caret.origin) {
            rect.origin.x = caret.minX
        }
        return rect
    }

    private func caretScreenRect(in textView: NSTextView) -> NSRect {
        let range = textView.selectedRange()
        let first = textView.firstRect(forCharacterRange: range, actualRange: nil)
        if let window = textView.window {
            let viewRect = window.convertToScreen(textView.convert(textView.bounds, to: nil)).insetBy(dx: -48, dy: -48)
            if viewRect.contains(first.origin) || viewRect.intersects(first) {
                return first
            }
        }
        guard let window = textView.window else { return first }
        var local = NSRect(
            x: textView.textContainerInset.width,
            y: textView.textContainerInset.height,
            width: 1,
            height: textView.font?.boundingRectForFont.height ?? 16
        )
        if let layout = textView.layoutManager, let container = textView.textContainer {
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 0), actualCharacterRange: nil)
            let used = layout.boundingRect(forGlyphRange: glyphs, in: container)
            if !used.isEmpty {
                local = used.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            }
        }
        return window.convertToScreen(textView.convert(local, to: nil))
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
            ?? makeCell(id)
        cell.textField?.stringValue = displayText(item)
        cell.imageView?.image = NSImage(systemSymbolName: symbol(item.kind), accessibilityDescription: nil)
        return cell
    }

    private func displayText(_ item: SQLCompletionItem) -> String {
        item.detail.map { "\(item.label)  \($0)" } ?? item.label
    }

    private func preferredWidth(for items: [SQLCompletionItem]) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var maxText: CGFloat = 0
        for item in items {
            let text = displayText(item) as NSString
            maxText = max(maxText, text.size(withAttributes: [.font: font]).width)
        }
        let chrome: CGFloat = 8 + 14 + 6 + 16
        return min(520, max(240, ceil(maxText) + chrome))
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        image.contentTintColor = .secondaryLabelColor
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.lineBreakMode = .byTruncatingTail
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cell.addSubview(image)
        cell.addSubview(text)
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 14),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func symbol(_ kind: SQLCompletionKind) -> String {
        switch kind {
        case .keyword: "textformat"
        case .table: "tablecells"
        case .view: "eye"
        case .column: "rectangle.split.3x1"
        }
    }
}
