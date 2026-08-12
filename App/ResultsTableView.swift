import SwiftUI
import AppKit
import SQLGrid
import SQLDrivers
import SQLUI
import SQLCore
import SQLImportExport

struct ResultsTableView: View {
    let model: ResultSetModel
    let filterText: String
    @Binding var sortOrdinal: Int?
    @Binding var sortAscending: Bool
    @Binding var selectedIDs: Set<Int>
    var isEditable: Bool = false
    var onEditCell: ((Int, Int, SQLValue) -> Void)?
    var onCopied: ((Int) -> Void)?

    @Environment(WorkspaceModel.self) private var workspace

    @State private var editing: CellEditTarget?
    @State private var editDraft = ""
    @FocusState private var editFieldFocused: Bool
    @FocusState private var tableFocused: Bool
    @State private var selection = ResultRowSelection()
    @State private var widthOverrides: [Int: CGFloat] = [:]
    @State private var resizeSession: (ordinal: Int, startWidth: CGFloat)?
    @State private var hoveringResizeOrdinal: Int?
    @State private var hoveringIndexID: Int?
    @State private var rubberBand: CGRect?

    private let rowHeight: CGFloat = 28
    private let headerHeight: CGFloat = 32
    private let indexWidth: CGFloat = 48
    private let hPad: CGFloat = 10
    private let resizeHandleWidth: CGFloat = 8

    private var columnWidths: [CGFloat] {
        model.columns.map { effectiveWidth(for: $0) }
    }

    private var tableWidth: CGFloat {
        indexWidth + columnWidths.reduce(0, +)
    }

    private var columnSignature: String {
        model.columns.map { "\($0.ordinal):\($0.name)" }.joined(separator: "|")
    }

    private var displayRows: [ResultTableRow] {
        let built = ResultDisplayRows.build(
            model: model,
            filterText: filterText,
            sortOrdinal: sortOrdinal,
            sortAscending: sortAscending
        )
        return built.enumerated().map { index, row in
            ResultTableRow(id: row.id, number: index + 1, values: row.values)
        }
    }

    var body: some View {
        GeometryReader { geo in
            tableScroll(geo: geo)
                .background(Color(nsColor: .textBackgroundColor))
                .background { copyFocusSink }
                .onReceive(NotificationCenter.default.publisher(for: .sexiqlCopySelectedRows)) { _ in
                    copySelected(format: workspace.copySelectedRowsFormat)
                }
                .onDisappear {
                    workspace.copySelectedRowsHandler = nil
                }
            .onChange(of: editing) { _, newValue in
                if newValue != nil {
                    DispatchQueue.main.async {
                        editFieldFocused = true
                    }
                }
                refreshCopyHandler()
            }
                .onChange(of: columnSignature) { _, _ in
                    pruneWidthOverrides()
                }
                .onChange(of: filterText) { _, _ in
                    pruneSelection(visibleIDs: Set(displayRows.map(\.id)))
                }
                .onChange(of: sortOrdinal) { _, _ in
                    pruneSelection(visibleIDs: Set(displayRows.map(\.id)))
                }
                .onChange(of: sortAscending) { _, _ in
                    pruneSelection(visibleIDs: Set(displayRows.map(\.id)))
                }
            .onChange(of: selectedIDs) { _, newValue in
                if newValue != selection.selectedIDs {
                    selection = ResultRowSelection(selectedIDs: newValue, anchorID: selection.anchorID)
                }
                refreshCopyHandler()
            }
                .onAppear {
                    pruneWidthOverrides()
                    if !selectedIDs.isEmpty {
                        selection = ResultRowSelection(selectedIDs: selectedIDs, anchorID: selection.anchorID)
                    }
                }
        }
    }

    private var copyFocusSink: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .focusable()
            .focused($tableFocused)
            .onCopyCommand {
                copyCommandProviders(format: workspace.copySelectedRowsFormat)
            }
            .onExitCommand {
                if editing != nil {
                    cancelEdit()
                } else {
                    clearSelection()
                }
            }
    }

    private func tableScroll(geo: GeometryProxy) -> some View {
        let rows = displayRows
        let displayIDs = rows.map(\.id)
        let widths = columnWidths
        let contentW = max(tableWidth, geo.size.width)
        let fill = max(0, geo.size.height - headerHeight - CGFloat(rows.count) * rowHeight)

        return ScrollView([.horizontal, .vertical], showsIndicators: true) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if rows.isEmpty {
                        emptyBody(
                            width: contentW,
                            minHeight: max(80, geo.size.height - headerHeight)
                        )
                    } else {
                        rowsBody(
                            rows: rows,
                            displayIDs: displayIDs,
                            widths: widths,
                            contentW: contentW,
                            fill: fill
                        )
                    }
                } header: {
                    headerRow(widths: widths, totalWidth: contentW)
                }
            }
            .frame(minWidth: contentW, alignment: .topLeading)
        }
    }

    private func rowsBody(
        rows: [ResultTableRow],
        displayIDs: [Int],
        widths: [CGFloat],
        contentW: CGFloat,
        fill: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                dataRow(row, widths: widths, totalWidth: contentW, displayIDs: displayIDs)
            }
            if fill > 0 {
                Color(nsColor: .textBackgroundColor)
                    .frame(width: contentW, height: fill)
                    .contentShape(Rectangle())
                    .onTapGesture { clearSelection() }
            }
        }
        .coordinateSpace(name: "resultRows")
        .overlay(alignment: .topLeading) {
            if let rubberBand {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(Rectangle().stroke(Color.accentColor.opacity(0.85), lineWidth: 1))
                    .frame(width: max(rubberBand.width, 1), height: max(rubberBand.height, 1))
                    .offset(x: rubberBand.minX, y: rubberBand.minY)
                    .allowsHitTesting(false)
            }
        }
        .gesture(marqueeGesture(displayIDs: displayIDs))
    }

    // MARK: - Header

    private func headerRow(widths: [CGFloat], totalWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            headerCell("#", type: nil, width: indexWidth, align: .center, ordinal: nil)

            ForEach(Array(model.columns.enumerated()), id: \.element.id) { index, column in
                let w = index < widths.count ? widths[index] : 120
                headerCell(
                    column.name,
                    type: column.dataType.isEmpty ? nil : column.dataType,
                    width: w,
                    align: .leading,
                    ordinal: column.ordinal
                )
            }

            if totalWidth > tableWidth {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: totalWidth - tableWidth, height: headerHeight)
            }
        }
        .frame(height: headerHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: 1)
        }
    }

    private func headerCell(
        _ name: String,
        type: String?,
        width: CGFloat,
        align: Alignment,
        ordinal: Int?
    ) -> some View {
        ZStack(alignment: .trailing) {
            Button {
                if let ordinal {
                    toggleSort(ordinal)
                }
            } label: {
                HStack(spacing: 6) {
                    if align == .center {
                        Spacer(minLength: 0)
                    }
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let type {
                        Text(type)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let ordinal, sortOrdinal == ordinal {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, hPad)
                .padding(.trailing, ordinal != nil ? resizeHandleWidth / 2 : 0)
                .frame(width: width, height: headerHeight, alignment: align)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let ordinal {
                columnResizeHandle(ordinal: ordinal, currentWidth: width, columnName: name)
            } else if name == "#" {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                    .frame(width: 1, height: 16)
                    .padding(.trailing, 0)
            }
        }
        .frame(width: width, height: headerHeight)
    }

    private func columnResizeHandle(ordinal: Int, currentWidth: CGFloat, columnName: String) -> some View {
        let active = hoveringResizeOrdinal == ordinal || resizeSession?.ordinal == ordinal
        return ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(active ? 0.85 : 0.35))
                .frame(width: active ? 2 : 1, height: active ? headerHeight - 4 : 16)
            Color.clear
                .frame(width: resizeHandleWidth, height: headerHeight)
                .contentShape(Rectangle())
        }
        .frame(width: resizeHandleWidth, height: headerHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveringResizeOrdinal = ordinal
                NSCursor.resizeLeftRight.set()
            } else if hoveringResizeOrdinal == ordinal {
                hoveringResizeOrdinal = nil
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    if resizeSession?.ordinal != ordinal {
                        resizeSession = (ordinal, currentWidth)
                    }
                    guard let session = resizeSession, session.ordinal == ordinal else { return }
                    let next = Self.clampedWidth(session.startWidth + value.translation.width)
                    widthOverrides[ordinal] = next
                }
                .onEnded { _ in
                    resizeSession = nil
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                widthOverrides[ordinal] = nil
                resizeSession = nil
            }
        )
        .help("Drag to resize. Double-click to auto-size.")
        .accessibilityLabel("Resize column \(columnName)")
    }

    // MARK: - Data rows

    private func dataRow(
        _ row: ResultTableRow,
        widths: [CGFloat],
        totalWidth: CGFloat,
        displayIDs: [Int]
    ) -> some View {
        let isSelected = selection.selectedIDs.contains(row.id)
        return HStack(spacing: 0) {
            indexGutter(row, isSelected: isSelected)

            ForEach(Array(model.columns.enumerated()), id: \.element.id) { index, column in
                let w = index < widths.count ? widths[index] : 120
                let target = CellEditTarget(modelRow: row.id, column: column.ordinal)
                let isEditing = editing == target

                Group {
                    if isEditing {
                        TextField("", text: $editDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    )
                            )
                            .focused($editFieldFocused)
                            .onSubmit { commitEdit() }
                            .onExitCommand { cancelEdit() }
                    } else {
                        cell(row.value(at: column.ordinal))
                    }
                }
                .padding(.horizontal, isEditing ? 4 : hPad)
                .frame(width: w, height: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if isEditable, !isEditing {
                            beginEdit(row: row.id, column: column.ordinal)
                        }
                    }
                )
                .contextMenu {
                    Button("Copy") { copyFromMenu(rowID: row.id) }
                    Button("Copy as CSV") { copyFromMenu(rowID: row.id, format: .csv) }
                    Button("Copy as JSON") { copyFromMenu(rowID: row.id, format: .json) }
                    Button("Copy as VALUES") { copyFromMenu(rowID: row.id, valuesSQL: true) }
                    if isEditable {
                        Divider()
                        Button("Edit…") {
                            beginEdit(row: row.id, column: column.ordinal)
                        }
                        Button("Set to NULL") {
                            onEditCell?(row.id, column.ordinal, .null)
                        }
                    }
                }
                .overlay(alignment: .trailing) {
                    if index < model.columns.count - 1 {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.25))
                            .frame(width: 1, height: rowHeight - 8)
                    }
                }
            }

            if totalWidth > tableWidth {
                Color.clear
                    .frame(width: totalWidth - tableWidth, height: rowHeight)
            }
        }
        .frame(height: rowHeight)
        .background {
            if isSelected {
                SexiQLColors.selectionFill
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.12))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleRowClick(row.id, displayIDs: displayIDs)
        }
        .contextMenu {
            Button("Copy") { copyFromMenu(rowID: row.id) }
            Button("Copy as CSV") { copyFromMenu(rowID: row.id, format: .csv) }
            Button("Copy as JSON") { copyFromMenu(rowID: row.id, format: .json) }
            Button("Copy as VALUES") { copyFromMenu(rowID: row.id, valuesSQL: true) }
        }
    }

    private func indexGutter(
        _ row: ResultTableRow,
        isSelected: Bool
    ) -> some View {
        Text("\(row.number)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(isSelected ? .primary : .tertiary)
            .frame(width: indexWidth, height: rowHeight, alignment: .trailing)
            .padding(.trailing, hPad)
            .contentShape(Rectangle())
            .background {
                if hoveringIndexID == row.id, !isSelected {
                    SexiQLColors.hoverFill
                }
            }
            .onHover { hovering in
                hoveringIndexID = hovering ? row.id : (hoveringIndexID == row.id ? nil : hoveringIndexID)
            }
    }

    @ViewBuilder
    private func cell(_ value: SQLValue) -> some View {
        if value == .null {
            Text("NULL")
                .font(.system(size: 12.5, design: .monospaced))
                .italic()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(value.displayString)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func emptyBody(width: CGFloat, minHeight: CGFloat) -> some View {
        Color(nsColor: .textBackgroundColor)
            .frame(width: width, height: max(minHeight, 80))
            .contentShape(Rectangle())
            .onTapGesture { clearSelection() }
            .overlay {
                if !filterText.isEmpty {
                    Text("No matching rows")
                        .font(SexiQLType.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
    }

    // MARK: - Selection / copy

    private func apply(_ next: ResultRowSelection, focus: Bool = true) {
        selection = next
        if selectedIDs != next.selectedIDs {
            selectedIDs = next.selectedIDs
        }
        if focus {
            tableFocused = true
        }
        refreshCopyHandler()
    }

    private func refreshCopyHandler() {
        if selection.isEmpty || editing != nil {
            workspace.copySelectedRowsHandler = nil
        } else {
            workspace.copySelectedRowsHandler = {
                NotificationCenter.default.post(name: .sexiqlCopySelectedRows, object: nil)
            }
        }
    }

    private func handleRowClick(_ id: Int, displayIDs: [Int]) {
        if editing != nil { commitEdit() }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        apply(
            ResultRowSelection.click(
                id: id,
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                current: selection,
                displayIDs: displayIDs
            )
        )
    }

    private func clearSelection() {
        guard !selection.isEmpty else { return }
        apply(ResultRowSelection(), focus: false)
    }

    private func marqueeGesture(displayIDs: [Int]) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("resultRows"))
            .onChanged { value in
                guard editing == nil, resizeSession == nil else { return }
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                rubberBand = rect
                guard let range = ResultRowSelection.indicesIntersecting(
                    minY: rect.minY,
                    maxY: rect.maxY,
                    rowHeight: rowHeight,
                    rowCount: displayIDs.count
                ) else { return }
                apply(
                    ResultRowSelection.gutterDrag(
                        from: displayIDs[range.lowerBound],
                        to: displayIDs[range.upperBound - 1],
                        displayIDs: displayIDs
                    )
                )
            }
            .onEnded { _ in
                rubberBand = nil
            }
    }

    private func pruneSelection(visibleIDs: Set<Int>) {
        apply(ResultRowSelection.prune(selection, visibleIDs: visibleIDs), focus: false)
    }

    private func copyFromMenu(rowID: Int, format: CopySelectedRowsFormat? = nil, valuesSQL: Bool = false) {
        let next = ResultRowSelection.prepareContextSelection(id: rowID, current: selection)
        apply(next)
        if valuesSQL {
            copySelectedValues(ids: next.selectedIDs)
        } else {
            copySelected(format: format ?? workspace.copySelectedRowsFormat, ids: next.selectedIDs)
        }
    }

    private func selectedValues(ids: Set<Int>) -> [[SQLValue]] {
        displayRows.filter { ids.contains($0.id) }.map(\.values)
    }

    private func copyCommandProviders(format: CopySelectedRowsFormat) -> [NSItemProvider] {
        guard let payload = encodedSelection(format: format) else { return [] }
        copyToPasteboard(payload.text)
        onCopied?(payload.rowCount)
        return [NSItemProvider(object: payload.text as NSString)]
    }

    private func encodedSelection(
        format: CopySelectedRowsFormat,
        ids: Set<Int>? = nil
    ) -> (text: String, rowCount: Int)? {
        if editing != nil { return nil }
        let useIDs = ids ?? selection.selectedIDs
        guard !useIDs.isEmpty else { return nil }
        let columns = model.columns.map(\.name)
        let rows = selectedValues(ids: useIDs)
        do {
            let content: String
            switch format {
            case .tsv:
                content = ResultDisplayRows.tsv(columns: columns, rows: rows)
            case .csv:
                content = CSVCodec.encode(columns: columns, rows: rows)
            case .json:
                content = try JSONCodec.encode(columns: columns, rows: rows)
            }
            return (content, rows.count)
        } catch {
            workspace.activeError = "Copy failed: \(error.localizedDescription)"
            return nil
        }
    }

    private func copySelected(format: CopySelectedRowsFormat, ids: Set<Int>? = nil) {
        guard let payload = encodedSelection(format: format, ids: ids) else { return }
        copyToPasteboard(payload.text)
        onCopied?(payload.rowCount)
    }

    private func copySelectedValues(ids: Set<Int>? = nil) {
        let useIDs = ids ?? selection.selectedIDs
        guard !useIDs.isEmpty else { return }
        let sql = ResultDisplayRows.valuesSQL(rows: selectedValues(ids: useIDs))
        guard !sql.isEmpty else { return }
        copyToPasteboard(sql)
        onCopied?(useIDs.count)
    }

    // MARK: - Editing

    private func beginEdit(row modelRow: Int, column: Int) {
        guard isEditable else { return }
        guard onEditCell != nil else { return }
        guard modelRow >= 0, modelRow < model.rows.count,
              column >= 0, column < model.columns.count else { return }
        if editing == CellEditTarget(modelRow: modelRow, column: column) {
            editFieldFocused = true
            return
        }
        if editing != nil {
            commitEdit()
        }
        let value = model[modelRow, column]
        editDraft = value == .null ? "" : value.displayString
        editing = CellEditTarget(modelRow: modelRow, column: column)
        DispatchQueue.main.async {
            editFieldFocused = true
        }
    }

    private func commitEdit() {
        guard let target = editing else { return }
        let newValue = Self.parsedValue(editDraft)
        editing = nil
        editFieldFocused = false
        onEditCell?(target.modelRow, target.column, newValue)
    }

    private func cancelEdit() {
        editing = nil
        editDraft = ""
        editFieldFocused = false
    }

    /// Same literal rules as the old AppKit grid editor.
    static func parsedValue(_ text: String) -> SQLValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .string("") }
        switch trimmed.uppercased() {
        case "NULL", "∅": return .null
        default: break
        }
        if ["true", "TRUE", "t"].contains(trimmed) { return .bool(true) }
        if ["false", "FALSE", "f"].contains(trimmed) { return .bool(false) }
        if let integer = Int64(trimmed) { return .int(integer) }
        if let double = Double(trimmed.replacingOccurrences(of: ",", with: ".")) { return .double(double) }
        return .string(text)
    }

    // MARK: - Sizing / sort

    private func effectiveWidth(for column: GridColumn) -> CGFloat {
        if let override = widthOverrides[column.ordinal] {
            return Self.clampedWidth(override)
        }
        return idealWidth(for: column)
    }

    private func idealWidth(for column: GridColumn) -> CGFloat {
        let nameW = CGFloat(column.name.count) * 7.6 + 20
        let typeW = column.dataType.isEmpty ? 0 : CGFloat(column.dataType.count) * 6.6 + 16
        var width = max(140, nameW + typeW)
        let ordinal = column.ordinal
        for row in model.rows.prefix(60) {
            guard ordinal < row.values.count else { continue }
            let text = row.values[ordinal] == .null ? "NULL" : row.values[ordinal].displayString
            width = max(width, CGFloat(min(text.count, 42)) * 7.5 + 28)
        }
        return Self.clampedWidth(min(max(width, 120), 420))
    }

    private static let widthClampMin: CGFloat = 80
    private static let widthClampMax: CGFloat = 720

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, widthClampMin), widthClampMax)
    }

    private func pruneWidthOverrides() {
        let valid = Set(model.columns.map(\.ordinal))
        widthOverrides = widthOverrides.filter { valid.contains($0.key) }
        if let session = resizeSession, !valid.contains(session.ordinal) {
            resizeSession = nil
        }
    }

    private func toggleSort(_ ordinal: Int) {
        // Don't start a sort while editing or resizing.
        if editing != nil || resizeSession != nil { return }
        if sortOrdinal == ordinal {
            if sortAscending {
                sortAscending = false
            } else {
                sortOrdinal = nil
                sortAscending = true
            }
        } else {
            sortOrdinal = ordinal
            sortAscending = true
        }
    }

}

// MARK: - Models

struct ResultTableRow: Identifiable, Equatable {
    let id: Int
    var number: Int = 0
    var values: [SQLValue]

    func value(at ordinal: Int) -> SQLValue {
        guard ordinal >= 0, ordinal < values.count else { return .null }
        return values[ordinal]
    }
}

struct CellEditTarget: Equatable {
    let modelRow: Int
    let column: Int
}
