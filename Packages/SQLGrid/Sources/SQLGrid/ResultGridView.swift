import AppKit
import SQLDrivers

public final class ResultGridView: NSTableView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    public static let rowIndexIdentifier = NSUserInterfaceItemIdentifier("row-index")
    public static let preferredRowHeight: CGFloat = 26
    public static let indexColumnWidth: CGFloat = 44

    private var model = ResultSetModel(columns: [])
    private var visibleRows: [Int] = []
    private var filterText = ""
    private var sortColumn: Int?
    private var sortAscending = true

    public var onEditCell: ((Int, Int, SQLValue) -> Void)?
    public var isEditable = false

    private var editorOverlay: NSTextField?
    private var overlayModelRow: Int?
    private var overlayColumn: Int?

    public init() {
        super.init(frame: .zero)
        dataSource = self
        delegate = self
        style = .plain
        usesAlternatingRowBackgroundColors = false
        backgroundColor = .textBackgroundColor
        allowsMultipleSelection = true
        allowsColumnReordering = false
        allowsColumnResizing = true
        columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        rowHeight = Self.preferredRowHeight
        usesAutomaticRowHeights = false
        intercellSpacing = NSSize(width: 1, height: 0)
        gridStyleMask = [.solidVerticalGridLineMask]
        gridColor = NSColor.separatorColor.withAlphaComponent(0.40)
        target = self
        doubleAction = #selector(handleDoubleClick)
        menu = buildContextMenu()
        configureChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func configureChrome() {
        backgroundColor = .textBackgroundColor
        if let scroll = enclosingScrollView {
            scroll.drawsBackground = true
            scroll.backgroundColor = .textBackgroundColor
            scroll.borderType = .noBorder
            scroll.contentView.drawsBackground = true
            scroll.contentView.backgroundColor = .textBackgroundColor
        }
        highlightedTableColumn = nil
    }

    public func applyScrollChrome() { configureChrome() }
    public func pinWidthToColumns() { sizeLastColumnToFit() }

    // MARK: - Debug / Bench

    public var columnIdentifiers: [String] {
        tableColumns.map(\.identifier.rawValue)
    }

    public var dataColumnsWidth: CGFloat {
        tableColumns.reduce(0) { $0 + $1.width }
    }

    public var totalColumnWidth: CGFloat { dataColumnsWidth }
    public var dataColumnCount: Int { model.columns.count }
    public var visibleRowCount: Int { visibleRows.count }

    public var labeledHeaderTitles: [String] {
        tableColumns.map(\.headerCell.stringValue)
    }

    // MARK: - Model

    public func setModel(_ newModel: ResultSetModel) {
        model = newModel
        rebuildColumns()
        recomputeVisibleRows()
        reloadData()
        configureChrome()
        sizeLastColumnToFit()
    }

    public func setFilter(_ text: String) {
        guard text != filterText else { return }
        filterText = text
        recomputeVisibleRows()
        reloadData()
    }

    // MARK: - Columns

    private func rebuildColumns() {
        while !tableColumns.isEmpty {
            removeTableColumn(tableColumns[tableColumns.count - 1])
        }

        let indexCol = NSTableColumn(identifier: Self.rowIndexIdentifier)
        indexCol.width = Self.indexColumnWidth
        indexCol.minWidth = Self.indexColumnWidth
        indexCol.maxWidth = Self.indexColumnWidth
        indexCol.resizingMask = []
        indexCol.headerCell.stringValue = "#"
        indexCol.headerCell.alignment = .center
        addTableColumn(indexCol)

        for (i, gridColumn) in model.columns.enumerated() {
            let id = NSUserInterfaceItemIdentifier("col-\(gridColumn.ordinal)")
            let col = NSTableColumn(identifier: id)
            let title: String
            if gridColumn.dataType.isEmpty {
                title = gridColumn.name
            } else {
                title = "\(gridColumn.name)  \(gridColumn.dataType)"
            }
            col.headerCell.stringValue = title
            col.headerCell.lineBreakMode = .byTruncatingTail
            col.minWidth = 80
            col.resizingMask = [.userResizingMask]
            col.sortDescriptorPrototype = NSSortDescriptor(key: id.rawValue, ascending: true)

            var width = ceil((title as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ]).width) + 24
            width = max(width, 100)
            for r in 0..<min(model.rows.count, 80) {
                let s = model[r, gridColumn.ordinal].displayString
                let tw = (s as NSString).size(withAttributes: [
                    .font: GridCellView.normalFont,
                ]).width + 24
                width = max(width, tw)
            }
            col.width = min(max(width, 100), 480)

            if i < model.columns.count - 1 {
                col.maxWidth = col.width
            } else {
                col.maxWidth = 10_000
            }
            addTableColumn(col)
        }

        sizeLastColumnToFit()
    }

    // MARK: - Sort / Filter

    private func recomputeVisibleRows() {
        visibleRows = ResultGridLogic.visibleIndices(
            model: model,
            filterText: filterText,
            sortColumn: sortColumn,
            sortAscending: sortAscending
        )
    }

    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        highlightedTableColumn = nil
        if let descriptor = tableView.sortDescriptors.first,
           let key = descriptor.key, key.hasPrefix("col-") {
            sortColumn = Int(key.replacingOccurrences(of: "col-", with: ""))
            sortAscending = descriptor.ascending
        } else {
            sortColumn = nil
        }
        recomputeVisibleRows()
        reloadData()
    }

    // MARK: - Data Source

    public func numberOfRows(in tableView: NSTableView) -> Int {
        visibleRows.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row >= 0, row < visibleRows.count else { return nil }

        if tableColumn.identifier == Self.rowIndexIdentifier {
            let id = Self.rowIndexIdentifier
            let cell: GridRowIndexCellView
            if let reused = makeView(withIdentifier: id, owner: nil) as? GridRowIndexCellView {
                cell = reused
            } else {
                cell = GridRowIndexCellView()
                cell.identifier = id
            }
            cell.configure(index: row + 1)
            return cell
        }

        guard let ordinal = modelColumnIndex(for: tableColumn) else { return nil }
        let cell: GridCellView
        if let reused = makeView(withIdentifier: tableColumn.identifier, owner: nil) as? GridCellView {
            cell = reused
        } else {
            cell = GridCellView()
            cell.identifier = tableColumn.identifier
        }
        let modelRow = visibleRows[row]
        let edited = model.editedCells.contains(CellKey(row: modelRow, column: ordinal))
        cell.configure(value: model[modelRow, ordinal], edited: edited)
        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = GridRowView.reuseID
        if let reused = makeView(withIdentifier: id, owner: nil) as? GridRowView {
            return reused
        }
        let view = GridRowView()
        view.identifier = id
        return view
    }

    private func modelColumnIndex(for tableColumn: NSTableColumn) -> Int? {
        let raw = tableColumn.identifier.rawValue
        guard raw.hasPrefix("col-") else { return nil }
        return Int(raw.dropFirst(4))
    }

    private func modelColumnIndex(atTableColumn idx: Int) -> Int? {
        guard tableColumns.indices.contains(idx) else { return nil }
        return modelColumnIndex(for: tableColumns[idx])
    }

    // MARK: - Editing

    @objc private func handleDoubleClick() {
        let row = clickedRow
        let column = clickedColumn
        guard isEditable, onEditCell != nil,
              row >= 0, column >= 0, row < visibleRows.count,
              let modelColumn = modelColumnIndex(atTableColumn: column) else { return }
        beginEditing(visibleRow: row, tableColumn: column, modelColumn: modelColumn)
    }

    private func beginEditing(visibleRow: Int, tableColumn: Int, modelColumn: Int) {
        let modelRow = visibleRows[visibleRow]
        let rect = frameOfCell(atColumn: tableColumn, row: visibleRow)
        let field = NSTextField(frame: rect.insetBy(dx: 1, dy: 1))
        field.font = GridCellView.normalFont
        field.delegate = self
        let value = model[modelRow, modelColumn]
        field.stringValue = value == .null ? "" : value.displayString
        addSubview(field)
        window?.makeFirstResponder(field)
        editorOverlay = field
        overlayModelRow = modelRow
        overlayColumn = modelColumn
    }

    private func commitOverlay() {
        guard let field = editorOverlay, let modelRow = overlayModelRow, let column = overlayColumn else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        editorOverlay = nil
        overlayModelRow = nil
        overlayColumn = nil
        onEditCell?(modelRow, column, Self.parsedValue(text))
    }

    private func cancelOverlay() {
        editorOverlay?.removeFromSuperview()
        editorOverlay = nil
        overlayModelRow = nil
        overlayColumn = nil
    }

    /// Stable Entry Point for Tests / Callers.
    public static func parsedValue(_ text: String) -> SQLValue {
        ResultGridLogic.parsedValue(text)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitOverlay(); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelOverlay(); return true
        }
        return false
    }

    @objc private func setNullOnSelectedCell(_ sender: Any?) {
        guard isEditable,
              let row = selectedRowIndexes.first,
              let tableCol = selectedColumnIndexes.first ?? dataTableColumnIndexes().first,
              let modelColumn = modelColumnIndex(atTableColumn: tableCol),
              row < visibleRows.count else {
            NSSound.beep(); return
        }
        onEditCell?(visibleRows[row], modelColumn, .null)
    }

    private func dataTableColumnIndexes() -> [Int] {
        tableColumns.indices.filter { modelColumnIndex(atTableColumn: $0) != nil }
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy Cells", action: #selector(copySelection(_:)), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        let sqlItem = NSMenuItem(title: "Copy Row as VALUES", action: #selector(copyRowAsSQL(_:)), keyEquivalent: "")
        sqlItem.target = self
        menu.addItem(sqlItem)
        if isEditable {
            let nullItem = NSMenuItem(title: "Set Cell to NULL", action: #selector(setNullOnSelectedCell(_:)), keyEquivalent: "")
            nullItem.target = self
            menu.addItem(nullItem)
        }
        return menu
    }

    @objc func copySelection(_ sender: Any?) {
        guard !selectedRowIndexes.isEmpty else { NSSound.beep(); return }
        let cols: IndexSet = selectedColumnIndexes.isEmpty
            ? IndexSet(dataTableColumnIndexes())
            : selectedColumnIndexes
        var lines: [String] = []
        for row in selectedRowIndexes.sorted() where row < visibleRows.count {
            let modelRow = visibleRows[row]
            var fields: [String] = []
            for tableCol in cols.sorted() {
                guard let modelColumn = modelColumnIndex(atTableColumn: tableCol) else { continue }
                fields.append(ResultGridLogic.tsvField(model[modelRow, modelColumn]))
            }
            lines.append(fields.joined(separator: "\t"))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc func copyRowAsSQL(_ sender: Any?) {
        guard let row = selectedRowIndexes.first, row < visibleRows.count else { NSSound.beep(); return }
        let modelRow = visibleRows[row]
        var fields: [SQLValue] = []
        for column in 0..<model.columns.count {
            fields.append(model[modelRow, column])
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ResultGridLogic.valuesSQL(fields: fields), forType: .string)
    }
}
