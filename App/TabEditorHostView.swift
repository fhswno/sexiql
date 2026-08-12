import AppKit
import SQLEditor
import SwiftUI

final class TabEditorHostView: NSView {
    var onTextChange: ((UUID, String) -> Void)?
    var onRun: ((UUID, String) -> Void)?
    var onSaveQuery: ((UUID, String) -> Void)?
    var completionCatalog: (() -> SQLCompletionCatalog)?
    var onNeedColumns: ((String) -> Void)?

    private(set) var selectTileCount: Int = 0
    private(set) var externalHighlightCount: Int = 0

    private final class Pane {
        let tabID: UUID
        let scrollView: EditorScrollView
        let bridge: TextBridge
        var publishedText: String

        init(tabID: UUID, scrollView: EditorScrollView, bridge: TextBridge, text: String) {
            self.tabID = tabID
            self.scrollView = scrollView
            self.bridge = bridge
            self.publishedText = text
        }
    }

    private final class TextBridge: NSObject, NSTextViewDelegate {
        let tabID: UUID
        weak var host: TabEditorHostView?

        init(tabID: UUID, host: TabEditorHostView) {
            self.tabID = tabID
            self.host = host
        }

        func textDidChange(_ notification: Notification) {
            guard let host,
                  let textView = notification.object as? NSTextView,
                  let pane = host.panes[tabID] else { return }
            let value = textView.string
            pane.publishedText = value
            host.onTextChange?(tabID, value)
            if let editor = textView as? SQLEditorTextView {
                editor.scheduleHighlight()
            }
            pane.scrollView.tileDocument()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            host?.panes[tabID]?.scrollView.gutterView.needsDisplay = true
        }
    }

    private var panes: [UUID: Pane] = [:]
    private(set) var selectedTabID: UUID?
    private var lastLaidOutSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let sizeChanged =
            abs(bounds.width - lastLaidOutSize.width) > 0.5
            || abs(bounds.height - lastLaidOutSize.height) > 0.5
        lastLaidOutSize = bounds.size

        for pane in panes.values where !pane.scrollView.isHidden {
            if pane.scrollView.frame != bounds {
                pane.scrollView.frame = bounds
            }
            if sizeChanged {
                pane.scrollView.tileDocument()
            }
        }
    }

    func syncOpenTabs(_ openTabIDs: [UUID], texts: [UUID: String]) {
        let openSet = Set(openTabIDs)
        for id in panes.keys where !openSet.contains(id) {
            panes[id]?.scrollView.removeFromSuperview()
            panes[id] = nil
        }
        for id in openTabIDs where panes[id] == nil {
            createPane(id: id, text: texts[id] ?? "")
        }
        applySelectionVisibility()
    }

    func select(_ tabID: UUID?) {
        if selectedTabID == tabID {
            applySelectionVisibility()
            return
        }
        selectedTabID = tabID
        applySelectionVisibility()

        guard let tabID, let pane = panes[tabID] else { return }
        let tv = pane.scrollView.editorTextView

        if pane.scrollView.frame.size != bounds.size || pane.scrollView.frame.origin != bounds.origin {
            pane.scrollView.frame = bounds
            pane.scrollView.tileDocument()
            selectTileCount += 1
        }

        if window?.firstResponder !== tv {
            window?.makeFirstResponder(tv)
        }
    }

    func applyExternalText(tabID: UUID, text: String) {
        guard let pane = panes[tabID] else { return }
        guard text != pane.publishedText else { return }
        let tv = pane.scrollView.editorTextView
        tv.string = text
        pane.publishedText = text
        tv.highlightNow()
        externalHighlightCount += 1
        pane.scrollView.tileDocument()
    }

    func applyAllExternalTexts(_ texts: [UUID: String]) {
        for (id, text) in texts {
            applyExternalText(tabID: id, text: text)
        }
    }

    func setActionHandlers(
        onTextChange: @escaping (UUID, String) -> Void,
        onRun: @escaping (UUID, String) -> Void,
        onSaveQuery: @escaping (UUID, String) -> Void,
        completionCatalog: @escaping () -> SQLCompletionCatalog,
        onNeedColumns: @escaping (String) -> Void
    ) {
        self.onTextChange = onTextChange
        self.onRun = onRun
        self.onSaveQuery = onSaveQuery
        self.completionCatalog = completionCatalog
        self.onNeedColumns = onNeedColumns
        for pane in panes.values {
            wireActions(for: pane)
        }
    }

    private func applySelectionVisibility() {
        for (id, pane) in panes {
            let hide = id != selectedTabID
            if pane.scrollView.isHidden != hide {
                pane.scrollView.isHidden = hide
            }
        }
    }

    private func createPane(id: UUID, text: String) {
        let scroll = EditorScrollView()
        scroll.frame = bounds.isEmpty ? NSRect(x: 0, y: 0, width: 100, height: 100) : bounds
        scroll.autoresizingMask = [.width, .height]

        let bridge = TextBridge(tabID: id, host: self)
        let tv = scroll.editorTextView
        tv.string = text
        tv.delegate = bridge
        tv.highlightNow()
        externalHighlightCount += 1
        scroll.tileDocument()

        let pane = Pane(tabID: id, scrollView: scroll, bridge: bridge, text: text)
        wireActions(for: pane)
        panes[id] = pane

        scroll.isHidden = id != selectedTabID
        addSubview(scroll)
    }

    private func wireActions(for pane: Pane) {
        let id = pane.tabID
        let tv = pane.scrollView.editorTextView
        tv.onRun = { [weak self] sql in
            self?.onRun?(id, sql)
        }
        tv.onSaveQuery = { [weak self] sql in
            self?.onSaveQuery?(id, sql)
        }
        tv.completionCatalog = { [weak self] in
            self?.completionCatalog?() ?? .keywordsOnly
        }
        tv.onNeedColumns = { [weak self] name in
            self?.onNeedColumns?(name)
        }
    }

    var activeTextView: SQLEditorTextView? {
        guard let selectedTabID else { return nil }
        return panes[selectedTabID]?.scrollView.editorTextView
    }

    var paneCount: Int { panes.count }

    @discardableResult
    func insertText(_ text: String, tabID: UUID) -> Bool {
        guard let pane = panes[tabID] else { return false }
        let tv = pane.scrollView.editorTextView
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: text) {
            tv.replaceCharacters(in: range, with: text)
            tv.didChangeText()
        } else {
            let ns = tv.string as NSString
            tv.string = ns.replacingCharacters(in: range, with: text)
        }
        let newLen = (text as NSString).length
        tv.setSelectedRange(NSRange(location: range.location + newLen, length: 0))
        pane.publishedText = tv.string
        tv.highlightNow()
        pane.scrollView.tileDocument()
        onTextChange?(tabID, tv.string)
        window?.makeFirstResponder(tv)
        return true
    }
}

// MARK: - SwiftUI bridge

struct TabEditorHostRepresentable: NSViewRepresentable {
    var openTabIDs: [UUID]
    var selectedTabID: UUID?
    var texts: [UUID: String]
    var contentEpoch: UInt64
    var onTextChange: (UUID, String) -> Void
    var onRun: (UUID, String) -> Void
    var onSaveQuery: (UUID, String) -> Void
    var completionCatalog: () -> SQLCompletionCatalog
    var onNeedColumns: (String) -> Void
    var onRegisterSQLProvider: ((TabEditorHostView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TabEditorHostView {
        let host = TabEditorHostView(frame: .zero)
        context.coordinator.bind(host: host, parent: self)
        host.syncOpenTabs(openTabIDs, texts: texts)
        host.select(selectedTabID)
        context.coordinator.lastOpenIDs = openTabIDs
        context.coordinator.lastSelected = selectedTabID
        context.coordinator.lastEpoch = contentEpoch
        return host
    }

    func updateNSView(_ host: TabEditorHostView, context: Context) {
        let coord = context.coordinator
        coord.bind(host: host, parent: self)

        if coord.lastOpenIDs != openTabIDs {
            host.syncOpenTabs(openTabIDs, texts: texts)
            coord.lastOpenIDs = openTabIDs
        }

        if coord.lastSelected != selectedTabID {
            host.select(selectedTabID)
            coord.lastSelected = selectedTabID
        }

        if coord.lastEpoch != contentEpoch {
            host.applyAllExternalTexts(texts)
            coord.lastEpoch = contentEpoch
        }
    }

    @MainActor
    final class Coordinator {
        var lastOpenIDs: [UUID] = []
        var lastSelected: UUID?
        var lastEpoch: UInt64 = .max

        func bind(host: TabEditorHostView, parent: TabEditorHostRepresentable) {
            host.setActionHandlers(
                onTextChange: parent.onTextChange,
                onRun: parent.onRun,
                onSaveQuery: parent.onSaveQuery,
                completionCatalog: parent.completionCatalog,
                onNeedColumns: parent.onNeedColumns
            )
            parent.onRegisterSQLProvider?(host)
        }
    }
}
