import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - Execution

    func explain(_ tabID: UUID, sql overrideSQL: String? = nil) {
        guard document.openTabs.contains(where: { $0.id == tabID }) else { return }
        guard let profileID = ensureTabHasConnection(tabID) else {
            activeError = "Select a connection in the sidebar before explaining."
            return
        }
        let sql = resolveSQLToRun(tabID: tabID, override: overrideSQL)
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if resultsCollapsed { resultsCollapsed = false }
        explainingTabs.insert(tabID)
        explainPlans[tabID] = nil
        explainErrors[tabID] = nil
        Task {
            defer { explainingTabs.remove(tabID) }
            do {
                guard let profile = document.connections.first(where: { $0.id == profileID }),
                      let connection = await awaitConnection(profileID) else {
                    throw SQLDriverError.connectionFailed(message: "Not connected")
                }
                let explainSQL: String
                switch profile.kind {
                case .postgres:
                    explainSQL = "EXPLAIN (FORMAT JSON) \(sql)"
                case .mysql:
                    explainSQL = "EXPLAIN FORMAT=JSON \(sql)"
                case .sqlite:
                    explainSQL = "EXPLAIN QUERY PLAN \(sql)"
                case .redis:
                    throw SQLDriverError.notImplemented(feature: "Explain is not available for Redis")
                }
                let result = try await connection.execute(explainSQL)
                let parser = ExplainParser()
                let plan: ExplainNode?
                if profile.kind == .sqlite {
                    let rows = result.rows.map { row in row.values.map(\.displayString) }
                    plan = try parser.parse(sqliteRows: rows)
                } else {
                    guard let firstValue = result.rows.first?.values.first else {
                        throw ExplainError.malformedJSON
                    }
                    let json: String
                    switch firstValue {
                    case .string(let value): json = value
                    case .data(let value): json = String(decoding: value, as: UTF8.self)
                    default: json = firstValue.displayString
                    }
                    plan = try profile.kind == .mysql
                        ? parser.parse(mysqlJSONData: Data(json.utf8))
                        : parser.parse(jsonData: Data(json.utf8))
                }
                if let plan {
                    explainPlans[tabID] = plan
                } else {
                    throw ExplainError.malformedJSON
                }
            } catch {
                explainErrors[tabID] = error.localizedDescription
            }
        }
    }

    func clearExplain(_ tabID: UUID) {
        explainPlans[tabID] = nil
        explainErrors[tabID] = nil
    }

    func run(_ tabID: UUID, sql overrideSQL: String? = nil) {
        guard document.openTabs.contains(where: { $0.id == tabID }) else { return }
        guard let profileID = ensureTabHasConnection(tabID) else {
            activeError = "Select a connection in the sidebar before running."
            return
        }
        if isProfileBusy(profileID), runTasks[tabID] == nil {
            if hasLiveRun(on: profileID) {
                activeError = "A query is already running on this connection. Stop it first."
                return
            }
            busyProfileIDs.remove(profileID)
        }

        let text = resolveSQLToRun(tabID: tabID, override: overrideSQL)
        let kind = document.connections.first(where: { $0.id == profileID })?.kind
        if kind != .redis, !SQLPayloadGuard.looksLikeSQL(text) {
            let state = StatementResult(label: text)
            state.status = .failed
            state.message = "Doesn't look like SQL — is an error still in the editor?"
            results[tabID] = [state]
            selectedResultIndex[tabID] = 0
            if resultsCollapsed { resultsCollapsed = false }
            return
        }
        if let profile = document.connections.first(where: { $0.id == profileID }),
           profile.readOnly,
           StatementWriteGuard.isWrite(text, kind: profile.kind) {
            activeError = "Connection is read-only."
            return
        }
        let statements: [SQLStatement]
        if kind == .redis {
            statements = RedisCommand.splitStatements(text).map { SQLStatement(text: $0) }
        } else {
            statements = SQLStatementSplitter().split(text)
        }
        guard !statements.isEmpty else { return }

        explainPlans[tabID] = nil
        explainErrors[tabID] = nil

        let hadInFlight = runTasks[tabID] != nil || runningTabs.contains(tabID)
        if hadInFlight {
            runTasks[tabID]?.cancel()
            runTasks[tabID] = nil
            runTokens[tabID] = nil
            runningTabs.remove(tabID)
            finalizeCancelledResults(tabID)
        }

        if resultsCollapsed { resultsCollapsed = false }

        let resultStates = statements.map { StatementResult(label: $0.text) }
        results[tabID] = resultStates
        selectedResultIndex[tabID] = 0
        activeError = nil
        maybeAutoTitleTab(tabID, fromSQL: tabTexts[tabID] ?? text)
        runningTabs.insert(tabID)
        markProfileBusy(profileID)
        let runToken = UUID()
        runTokens[tabID] = runToken
        runTasks[tabID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.runTokens[tabID] == runToken {
                    self.runTasks[tabID] = nil
                    self.runTokens[tabID] = nil
                    self.runningTabs.remove(tabID)
                    self.unmarkProfileBusy(profileID)
                }
            }
            if hadInFlight {
                await self.cancelInFlightAndReconnectIfNeeded(profileID)
            }
            guard !Task.isCancelled else { return }
            await self.executeStatements(
                resultStates,
                statements: statements,
                profileID: profileID,
                tabID: tabID
            )
        }
    }

    func cancelRun(_ tabID: UUID, invokeDriverCancel: Bool = true) {
        let hadTask = runTasks[tabID] != nil || runningTabs.contains(tabID)
        let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID
            ?? selectedConnectionID
        runTasks[tabID]?.cancel()
        runTasks[tabID] = nil
        runTokens[tabID] = nil
        runningTabs.remove(tabID)
        if let profileID {
            unmarkProfileBusy(profileID)
        }
        if hadTask {
            finalizeCancelledResults(tabID)
        }
        guard hadTask else { return }
        if invokeDriverCancel, let profileID {
            Task { @MainActor [weak self] in
                await self?.cancelInFlightAndReconnectIfNeeded(profileID)
            }
        }
    }

    private func cancelInFlightAndReconnectIfNeeded(_ profileID: UUID) async {
        if let connection = await connectionManager.connection(for: profileID) {
            await connection.cancelInFlight()
            if await connection.isConnected() {
                return
            }
        }
        try? await connectionManager.disconnect(profileID)
        if let profile = document.connections.first(where: { $0.id == profileID }) {
            connect(profile)
        }
    }

    func finalizeCancelledResults(_ tabID: UUID) {
        guard let states = results[tabID] else { return }
        for state in states {
            switch state.status {
            case .pending, .running:
                state.status = .cancelled
                state.message = state.message ?? "Cancelled"
            case .streaming:
                state.status = .cancelled
                if state.message == nil {
                    let n = state.model.rows.count
                    state.message = n > 0 ? "Cancelled — \(n) row\(n == 1 ? "" : "s")" : "Cancelled"
                }
                if !state.model.columns.isEmpty {
                    state.model.finish(totalRowCount: state.model.rows.count)
                }
            case .complete, .failed, .cancelled:
                break
            }
        }
    }

    func resolveSQLToRun(tabID: UUID, override: String?) -> String {
        if let override {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return override }
        }
        if let live = activeSQLProvider?() {
            let trimmed = live.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return live }
        }
        return tabTexts[tabID] ?? ""
    }

    func executeStatements(
        _ states: [StatementResult],
        statements: [SQLStatement],
        profileID: UUID,
        tabID: UUID
    ) async {
        let start = Date()
        for (index, statement) in statements.enumerated() {
            if Task.isCancelled {
                for s in states where s.status == .pending || s.status == .running || s.status == .streaming {
                    if s.status == .streaming, !s.model.columns.isEmpty {
                        s.model.finish(totalRowCount: s.model.rows.count)
                    }
                    s.status = .cancelled
                    s.message = s.message ?? "Cancelled"
                }
                return
            }
            let state = states[index]
            var retriedSend = false
            statementAttempt: while true {
                do {
                    guard let connection = await awaitConnection(profileID) else {
                        state.status = .failed
                        state.message = "Not connected"
                        return
                    }
                    let kind = document.connections.first(where: { $0.id == profileID })?.kind
                    let guarded: SQLLimitGuard.Outcome
                    if kind == .redis {
                        guarded = SQLLimitGuard.Outcome(sql: statement.text, didLimit: false)
                    } else {
                        guarded = SQLLimitGuard().apply(statement.text, limit: document.settings.resultRowLimit)
                    }
                    if guarded.didLimit {
                        state.appliedLimit = document.settings.resultRowLimit
                    }
                    if kind != .redis, SQLStreamability.isStreamable(statement.text) {
                        state.status = .streaming
                        let streamed = try await connection.stream(guarded.sql)
                        state.sqlColumns = streamed.columns
                        state.model = ResultSetModel(columns: streamed.columns.map {
                            GridColumn(ordinal: $0.ordinal, name: $0.name, dataType: $0.dataType)
                        })
                        let outcome = await StreamingAdapter().consume(streamed.rows, initialColumns: state.model.columns) { model in
                            state.model = model
                        }
                        if Task.isCancelled || state.status == .cancelled {
                            keepCancelled(state, rows: state.model.rows.count, start: start)
                            markRemainingCancelled(states, after: index)
                            return
                        }
                        switch outcome {
                        case .success(let finalModel):
                            state.model = finalModel
                            state.status = .complete
                        case .failure(let error):
                            let stopped = Task.isCancelled || state.status == .cancelled
                            if stopped || SQLStreamability.isCancellation(error, userCancelled: stopped) {
                                keepCancelled(state, rows: state.model.rows.count, start: start)
                            } else {
                                state.status = .failed
                                state.message = annotatedQueryError(error, profileID: profileID)
                                state.duration = Date().timeIntervalSince(start)
                            }
                            markRemainingCancelled(states, after: index)
                            return
                        }
                    } else {
                        state.status = .running
                        let result = try await connection.execute(guarded.sql)
                        if Task.isCancelled {
                            state.status = .cancelled
                            state.message = "Cancelled"
                            state.duration = Date().timeIntervalSince(start)
                            markRemainingCancelled(states, after: index)
                            return
                        }
                        if let columns = result.columns {
                            state.sqlColumns = columns
                            state.model = ResultSetModel(
                                columns: columns.map { GridColumn(ordinal: $0.ordinal, name: $0.name, dataType: $0.dataType) },
                                rows: result.rows,
                                isComplete: true
                            )
                            state.status = .complete
                        } else {
                            state.status = .complete
                            state.message = result.affectedRowCount.map { "\($0) row(s) affected" } ?? "OK"
                        }
                    }
                    state.duration = Date().timeIntervalSince(start)
                    recordHistory(statement.text, profileID: profileID)
                    if Self.statementChangesSchema(statement.text) {
                        refreshSchema(for: profileID)
                    }
                    if state.status == .complete, !state.sqlColumns.isEmpty {
                        Task { await resolveEditable(for: state, profileID: profileID) }
                    }
                    break statementAttempt
                    } catch is CancellationError {
                    keepCancelled(state, start: start)
                    markRemainingCancelled(states, after: index)
                    return
                } catch {
                    let stopped = Task.isCancelled || state.status == .cancelled
                    if stopped || SQLStreamability.isCancellation(error, userCancelled: stopped) {
                        keepCancelled(state, start: start)
                        markRemainingCancelled(states, after: index)
                        return
                    }
                    if !retriedSend, !stopped, Self.isRetryableSendFailure(error) {
                        retriedSend = true
                        continue
                    }
                    state.status = .failed
                    state.message = annotatedQueryError(error, profileID: profileID)
                    state.duration = Date().timeIntervalSince(start)
                    markRemainingCancelled(states, after: index)
                    return
                }
            }
        }
    }

    func annotatedQueryError(_ error: Error, profileID: UUID) -> String {
        let text = error.localizedDescription
        guard let pg = error as? PGError, pg.code == "42P01" else { return text }
        let name = missingRelationName(in: pg.message)
        guard let name else { return text }
        let objects = schemaByProfile[profileID]?.objects ?? schemaObjects
        let matches = objects.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard !matches.isEmpty else { return text }
        let qualified = matches.map(\.displayName).joined(separator: ", ")
        return text + "\nHint: qualify as \(qualified)"
    }

    func missingRelationName(in message: String) -> String? {
        guard let start = message.firstIndex(of: "\""),
              let end = message[message.index(after: start)...].firstIndex(of: "\"") else {
            return nil
        }
        let name = String(message[message.index(after: start)..<end])
        return name.isEmpty ? nil : name
    }

    static func statementChangesSchema(_ sql: String) -> Bool {
        let head = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for prefix in ["CREATE", "ALTER", "DROP", "RENAME", "DEL", "UNLINK", "SET", "HSET", "HDEL",
                       "SADD", "SREM", "ZADD", "ZREM", "LPUSH", "RPUSH", "LSET", "FLUSHDB", "FLUSHALL"] {
            if head.hasPrefix(prefix) && (head.count == prefix.count || head[head.index(head.startIndex, offsetBy: prefix.count)].isWhitespace) {
                return true
            }
            if head.hasPrefix(prefix + " ") { return true }
        }
        return false
    }

    private func keepCancelled(_ state: StatementResult, rows: Int? = nil, start: Date) {
        if state.status != .cancelled {
            state.status = .cancelled
        }
        if state.message == nil {
            if let rows, rows > 0 {
                state.message = "Cancelled — \(rows) row\(rows == 1 ? "" : "s")"
            } else {
                state.message = "Cancelled"
            }
        }
        if state.duration == nil {
            state.duration = Date().timeIntervalSince(start)
        }
    }

    func markRemainingCancelled(_ states: [StatementResult], after index: Int) {
        guard index + 1 < states.count else { return }
        for s in states[(index + 1)...] where s.status == .pending {
            s.status = .cancelled
            s.message = "Cancelled"
        }
    }

    static func isRetryableSendFailure(_ error: Error) -> Bool {
        if let pg = error as? PGError {
            return pg.isRetryableSendFailure
        }
        if case .connectionFailed(let message) = error as? SQLDriverError {
            return message.lowercased().contains("not connected")
        }
        return false
    }

    func awaitConnection(_ profileID: UUID) async -> (any DatabaseConnection)? {
        if let connection = await liveConnection(profileID) {
            return connection
        }
        if case .connecting = connectionStatuses[profileID] {
            var waited = 0.0
            while waited < 15 {
                try? await Task.sleep(for: .milliseconds(50))
                if let connection = await liveConnection(profileID) {
                    return connection
                }
                waited += 0.05
            }
        }
        return await reconnectIfNeeded(profileID)
    }

    private func liveConnection(_ profileID: UUID) async -> (any DatabaseConnection)? {
        guard let connection = await connectionManager.connection(for: profileID),
              await connection.isConnected() else {
            return nil
        }
        return connection
    }

    private func reconnectIfNeeded(_ profileID: UUID) async -> (any DatabaseConnection)? {
        if let connection = await liveConnection(profileID) {
            return connection
        }
        guard let profile = document.connections.first(where: { $0.id == profileID }) else {
            return nil
        }
        do {
            let connection = try await connectionManager.connect(profile)
            connectionStatuses[profileID] = .connected
            lastConnectionErrors[profileID] = nil
            return connection
        } catch {
            return nil
        }
    }
}
