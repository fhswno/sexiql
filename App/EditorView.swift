import SwiftUI
import AppKit
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLDrivers
import SQLUI

struct ResultsPaneView: View {
    @Environment(WorkspaceModel.self) private var model
    let tabID: UUID

    @State private var sortOrdinal: Int?
    @State private var sortAscending = true
    @State private var selectedRowIDs: Set<Int> = []
    @State private var inspectedCell: CellEditTarget?
    @State private var requestedEdit: CellEditTarget?
    @State private var copyFeedback: String?

    private var tabIsReadOnly: Bool {
        let profileID = model.document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID
        return profileID.flatMap { id in
            model.document.connections.first(where: { $0.id == id })?.readOnly
        } == true
    }

    var body: some View {
        Group {
            if let plan = model.explainPlans[tabID] {
                ExplainView(tabID: tabID, plan: plan)
            } else if let error = model.explainErrors[tabID] {
                QueryErrorView(
                    title: "Explain failed",
                    message: error,
                    onDismiss: { model.clearExplain(tabID) }
                )
            } else if let results = model.results[tabID], !results.isEmpty {
                VStack(spacing: 0) {
                    resultTabs(results)
                    resultBody(results)
                }
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .background {
            OutsideClickMonitor(enabled: !selectedRowIDs.isEmpty) {
                selectedRowIDs = []
            }
        }
        .onChange(of: selectedResultIdentity) { _, _ in
            selectedRowIDs = []
            inspectedCell = nil
        }
    }

    private var selectedResultIdentity: String {
        guard let results = model.results[tabID], !results.isEmpty else { return "" }
        let index = model.selectedResultIndex[tabID] ?? 0
        let result = results.indices.contains(index) ? results[index] : results[0]
        return result.id.uuidString
    }

    private func resultTabs(_ results: [StatementResult]) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SexiQLSpace.xs) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        Button {
                            model.selectedResultIndex[tabID] = index
                        } label: {
                            HStack(spacing: SexiQLSpace.sm) {
                                StatusDot(color: statusColor(result.status), size: 7)
                                Text(statementLabel(result.label))
                                    .font(SexiQLType.rowSubtitle)
                                    .lineLimit(1)
                                    .frame(maxWidth: 240, alignment: .leading)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                if (model.selectedResultIndex[tabID] ?? 0) == index {
                                    RoundedRectangle(cornerRadius: SexiQLRadius.sm, style: .continuous)
                                        .fill(SexiQLColors.selectionFillStrong)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(result.label)
                        .contextMenu {
                            if result.status == .failed {
                                Button("Fix with AI") {
                                    model.fixSQLWithAI(
                                        tabID: tabID,
                                        sql: result.label,
                                        error: result.message ?? "Query failed"
                                    )
                                }
                                Button("Ask in chat") {
                                    model.askAboutFailedSQL(
                                        tabID: tabID,
                                        sql: result.label,
                                        error: result.message ?? "Query failed"
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, SexiQLSpace.md)
                .padding(.vertical, SexiQLSpace.sm)
            }
            .background(Color(nsColor: .controlBackgroundColor))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
        }
    }

    private func statusColor(_ status: StatementResult.Status) -> Color {
        switch status {
        case .pending, .running, .streaming: SexiQLColors.connecting
        case .complete: SexiQLColors.connected
        case .failed: SexiQLColors.failed
        case .cancelled: SexiQLColors.disconnected
        }
    }

    private func statementLabel(_ sql: String) -> String {
        let collapsed = sql.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "(empty)" : collapsed
    }

    @ViewBuilder
    private func resultBody(_ results: [StatementResult]) -> some View {
        let index = min(model.selectedResultIndex[tabID] ?? 0, results.count - 1)
        let result = results[index]
        VStack(spacing: 0) {
            switch result.status {
            case .pending:
                ProgressView("Queued…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .running:
                waitingResult("Running…")
            case .streaming:
                if result.model.columns.isEmpty {
                    waitingResult("Streaming \(result.model.rows.count) rows…")
                } else {
                    populatedResult(result, index: index)
                }
            case .complete, .cancelled:
                if result.model.columns.isEmpty {
                    VStack(spacing: SexiQLSpace.md) {
                        Image(systemName: result.status == .cancelled ? "stop.circle" : "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(result.status == .cancelled ? SexiQLColors.disconnected : SexiQLColors.connected)
                        Text(result.message ?? (result.status == .cancelled ? "Cancelled" : "OK"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    populatedResult(result, index: index)
                }
            case .failed:
                QueryErrorView(
                    title: "Query failed",
                    message: result.message ?? "Query failed",
                    detailSQL: result.label,
                    onFix: {
                        model.fixSQLWithAI(
                            tabID: tabID,
                            sql: result.label,
                            error: result.message ?? "Query failed"
                        )
                    },
                    onAsk: {
                        model.askAboutFailedSQL(
                            tabID: tabID,
                            sql: result.label,
                            error: result.message ?? "Query failed"
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waitingResult(_ title: String) -> some View {
        VStack(spacing: SexiQLSpace.lg) {
            ProgressView()
            Text(title)
                .font(SexiQLType.rowSubtitle)
                .foregroundStyle(.secondary)
            Button("Stop") {
                model.cancelRun(tabID)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func populatedResult(_ result: StatementResult, index: Int) -> some View {
        if result.status == .cancelled, let message = result.message {
            HStack(spacing: SexiQLSpace.sm) {
                Image(systemName: "stop.circle")
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(SexiQLType.rowSubtitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.vertical, SexiQLSpace.sm)
            .background(Color.primary.opacity(0.04))
        }
        if result.status == .streaming {
            HStack(spacing: SexiQLSpace.sm) {
                ProgressView()
                    .controlSize(.mini)
                Text("Streaming \(result.model.rows.count) rows…")
                    .font(SexiQLType.rowSubtitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Stop") {
                    model.cancelRun(tabID)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.vertical, SexiQLSpace.sm)
            .background(Color.primary.opacity(0.04))
        }
        resultToolbar(result)
        ResultsTableView(
            model: result.model,
            filterText: result.filterText,
            sortOrdinal: $sortOrdinal,
            sortAscending: $sortAscending,
            selectedIDs: $selectedRowIDs,
            isEditable: result.editableTable != nil && result.status == .complete && !tabIsReadOnly,
            draftRowID: result.draftRowIndex,
            onEditCell: { row, column, value in
                model.handleCellEdit(
                    tabID: tabID,
                    resultIndex: index,
                    row: row,
                    column: column,
                    newValue: value
                )
            },
            onDeleteRows: { ids in
                model.requestDeleteResultRows(
                    tabID: tabID,
                    resultIndex: index,
                    rows: Array(ids)
                )
            },
            onCopied: { showCopyFeedback($0) },
            inspectedCell: $inspectedCell,
            requestedEdit: $requestedEdit
        )
        .onAppear { registerRowHandlers(result, index: index) }
        .onChange(of: selectedRowIDs) { _, _ in
            registerRowHandlers(result, index: index)
        }
        .onChange(of: result.editableTable != nil) { _, _ in
            registerRowHandlers(result, index: index)
        }
        .onChange(of: result.model.rows.count) { _, _ in
            selectedRowIDs = selectedRowIDs.filter { $0 < result.model.rows.count }
        }
        .onDisappear {
            model.addResultRowHandler = nil
            model.deleteResultRowsHandler = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if model.inspectorVisible {
            inspectorStrip(result)
        }
        statusBar(result)
    }

    private func resultToolbar(_ result: StatementResult) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: SexiQLSpace.md) {
                TextField("Filter rows…", text: Binding(
                    get: { result.filterText },
                    set: { result.filterText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

                if result.editableTable != nil {
                    Button {
                        model.addResultRow(tabID: tabID, resultIndex: resultIndex(of: result))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(tabIsReadOnly || model.isProfileBusy(model.document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID))
                    .help(tabIsReadOnly ? "Connection is read-only" : "Add row")

                    Button {
                        model.requestDeleteResultRows(
                            tabID: tabID,
                            resultIndex: resultIndex(of: result),
                            rows: Array(selectedRowIDs)
                        )
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(tabIsReadOnly || selectedRowIDs.isEmpty || model.isProfileBusy(model.document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID))
                    .help(selectedRowIDs.count > 1 ? "Delete \(selectedRowIDs.count) rows" : "Delete row")

                    Button {
                        model.undoLastEdit(tabID: tabID, resultIndex: resultIndex(of: result))
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(result.undoStack.isEmpty)
                    .help("Undo edit")

                    Button {
                        model.redoLastEdit(tabID: tabID, resultIndex: resultIndex(of: result))
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(result.redoStack.isEmpty)
                    .help("Redo edit")
                }

                Spacer(minLength: 0)

                if let copyFeedback {
                    Text(copyFeedback)
                        .font(SexiQLType.meta)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                Menu {
                    Button("Copy as CSV") { copyVisible(result, format: .csv) }
                    Button("Copy as JSON") { copyVisible(result, format: .json) }
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }
                .menuStyle(.borderlessButton)
                .help(selectedRowIDs.isEmpty
                      ? "Copy visible rows (respects filter and sort)"
                      : "Copy \(selectedRowIDs.count) selected row\(selectedRowIDs.count == 1 ? "" : "s")")

                Menu {
                    Button("CSV…") { export(result, format: .csv) }
                    Button("JSON…") { export(result, format: .json) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .help("Save full result set to a file")
            }
            .font(SexiQLType.rowTitle)
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)
        }
    }

    private func registerRowHandlers(_ result: StatementResult, index: Int) {
        let editable = result.editableTable != nil && result.status == .complete
        if editable {
            model.addResultRowHandler = { [weak model] in
                model?.addResultRow(tabID: tabID, resultIndex: index)
            }
            if selectedRowIDs.isEmpty {
                model.deleteResultRowsHandler = nil
            } else {
                let rows = Array(selectedRowIDs)
                model.deleteResultRowsHandler = { [weak model] in
                    model?.requestDeleteResultRows(tabID: tabID, resultIndex: index, rows: rows)
                }
            }
        } else {
            model.addResultRowHandler = nil
            model.deleteResultRowsHandler = nil
        }
    }

    @ViewBuilder
    private func inspectorStrip(_ result: StatementResult) -> some View {
        let target = inspectedCell
        let row = target?.modelRow
        let column = target?.column
        let value: SQLValue = {
            guard let row, let column, result.model.rows.indices.contains(row) else { return .null }
            return result.model[row, column]
        }()
        let columnName = column.flatMap { ordinal in
            result.model.columns.first(where: { $0.ordinal == ordinal })?.name
        } ?? "Value"
        let columnType = column.flatMap { ordinal in
            result.model.columns.first(where: { $0.ordinal == ordinal })?.dataType
        } ?? ""
        ValueInspectorView(
            columnName: columnName,
            columnType: columnType,
            value: value,
            onCopy: {
                copyToPasteboard(value == .null ? "NULL" : value.displayString)
                showCopyFeedback(1)
            },
            onEdit: result.editableTable != nil
                ? {
                    guard let row, let column else { return }
                    requestedEdit = CellEditTarget(modelRow: row, column: column)
                }
                : nil,
            onClose: { model.inspectorVisible = false }
        )
    }

    private func resultIndex(of result: StatementResult) -> Int {
        (model.results[tabID] ?? []).firstIndex(where: { $0.id == result.id }) ?? 0
    }

    private func copyVisible(_ result: StatementResult, format: ExportFormat) {
        do {
            let built = ResultDisplayRows.build(
                model: result.model,
                filterText: result.filterText,
                sortOrdinal: sortOrdinal,
                sortAscending: sortAscending
            )
            let rows: [[SQLValue]]
            if selectedRowIDs.isEmpty {
                rows = built.map(\.values)
            } else {
                rows = ResultDisplayRows.selected(from: built, ids: selectedRowIDs).map(\.values)
            }
            let columns = result.model.columns.map(\.name)
            let content: String
            switch format {
            case .csv:
                content = CSVCodec.encode(columns: columns, rows: rows)
            case .json:
                content = try JSONCodec.encode(columns: columns, rows: rows)
            }
            copyToPasteboard(content)
            showCopyFeedback(rows.count)
        } catch {
            model.activeError = "Copy failed: \(error.localizedDescription)"
        }
    }

    private func showCopyFeedback(_ n: Int) {
        withAnimation(.easeOut(duration: 0.12)) {
            copyFeedback = n == 1 ? "Copied 1 row" : "Copied \(n) rows"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeIn(duration: 0.2)) {
                if copyFeedback?.hasPrefix("Copied") == true {
                    copyFeedback = nil
                }
            }
        }
    }

    private func export(_ result: StatementResult, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format == .csv ? "result.csv" : "result.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let columns = result.model.columns.map(\.name)
            let rows = result.model.rows.map(\.values)
            let content: String
            switch format {
            case .csv:
                content = CSVCodec.encode(columns: columns, rows: rows)
            case .json:
                content = try JSONCodec.encode(columns: columns, rows: rows)
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.activeError = "Export failed: \(error.localizedDescription)"
        }
    }

    private enum ExportFormat {
        case csv
        case json
    }

    private func statusBar(_ result: StatementResult) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(height: 1)

            HStack(spacing: 0) {
                let rowCount = result.model.totalRowCount ?? result.model.rows.count
                let colCount = result.model.columns.count

                Text("\(rowCount) row\(rowCount == 1 ? "" : "s")")
                statusDot()
                Text("\(colCount) col\(colCount == 1 ? "" : "s")")

                if let duration = result.duration {
                    statusDot()
                    Text(String(format: "%.3fs", duration))
                }

                if let limit = result.appliedLimit {
                    statusDot()
                    Text("limited to \(limit)")
                }

                Spacer(minLength: SexiQLSpace.md)

                if let message = result.message, !message.isEmpty {
                    Text(message)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                inspectorToggle()
            }
            .font(SexiQLType.meta)
            .foregroundStyle(.secondary)
            .padding(.horizontal, SexiQLSpace.lg)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func statusDot() -> some View {
        Text("  ·  ")
            .foregroundStyle(.tertiary)
    }

    private func inspectorToggle() -> some View {
        Button {
            if inspectedCell == nil, let row = selectedRowIDs.min() {
                inspectedCell = CellEditTarget(modelRow: row, column: 0)
            }
            model.toggleInspector()
        } label: {
            Image(systemName: model.inspectorVisible ? "info.circle.fill" : "info.circle")
        }
        .buttonStyle(.borderless)
        .help(model.inspectorVisible ? "Hide value inspector" : "Inspect value (Space)")
        .padding(.leading, SexiQLSpace.sm)
    }
}

private struct QueryErrorView: View {
    let title: String
    let message: String
    var detailSQL: String? = nil
    var onDismiss: (() -> Void)? = nil
    var onFix: (() -> Void)? = nil
    var onAsk: (() -> Void)? = nil

    @State private var copied = false

    var body: some View {
        VStack(spacing: SexiQLSpace.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(SexiQLColors.failed)
            Text(title)
                .font(SexiQLType.rowTitle)
                .foregroundStyle(.primary)
            ScrollView {
                VStack(alignment: .leading, spacing: SexiQLSpace.sm) {
                    Text(message)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                    if let detailSQL, !detailSQL.isEmpty {
                        Divider()
                        Text("SQL sent")
                            .font(SexiQLType.meta)
                            .foregroundStyle(.tertiary)
                        Text(detailSQL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(SexiQLSpace.md)
                .background(
                    RoundedRectangle(cornerRadius: SexiQLRadius.sm, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SexiQLRadius.sm, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .frame(maxHeight: 280)
            HStack(spacing: SexiQLSpace.sm) {
                Button {
                    var paste = message
                    if let detailSQL, !detailSQL.isEmpty {
                        paste += "\n\n" + detailSQL
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(paste, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy Error", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if let onFix {
                    Button("Fix with AI", action: onFix)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if let onAsk {
                    Button("Ask in chat", action: onAsk)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if let onDismiss {
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .padding(SexiQLSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


