import AppKit
import Foundation
import SQLCore
import SQLDrivers
import SQLGrid
import SQLEditor
import SQLImportExport
import SQLExplainer

extension WorkspaceModel {
    // MARK: - AI Chat (Ollama)

    var aiEnabled: Bool {
        get { document.settings.aiEnabled }
        set {
            document.settings.aiEnabled = newValue
            saveWorkspace()
        }
    }

    var ollamaBaseURL: String {
        get { document.settings.ollamaBaseURL }
        set {
            document.settings.ollamaBaseURL = newValue
            scheduleSaveWorkspace()
        }
    }

    var ollamaModel: String {
        get { document.settings.ollamaModel }
        set {
            document.settings.ollamaModel = newValue
            scheduleSaveWorkspace()
        }
    }

    func aiMessages(for tabID: UUID?) -> [AIChatMessage] {
        guard let tabID else { return [] }
        return aiChatMessages[tabID] ?? []
    }

    func toggleAIPanel() {
        if aiPanelVisible {
            aiPanelVisible = false
        } else {
            openAIPanel()
        }
    }

    func openAIPanel() {
        aiPanelVisible = true
        if focusMode {
            exitFocusModeKeepingAI()
        }
    }

    func explainWithAI(_ tabID: UUID, sql overrideSQL: String? = nil) {
        guard document.openTabs.contains(where: { $0.id == tabID }) else { return }

        let sql = resolveSQLToRun(tabID: tabID, override: overrideSQL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else {
            openAIPanel()
            aiError[tabID] = "Nothing to explain. Select SQL or open a query tab."
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ready = await self.ensureAIReady(for: tabID, pending: .explain(tabID: tabID, sql: overrideSQL))
            guard ready else { return }
            self.startExplainTurn(tabID: tabID, sql: sql)
        }
    }

    func sendAIFollowUp(_ tabID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard document.openTabs.contains(where: { $0.id == tabID }) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ready = await self.ensureAIReady(for: tabID, pending: .explain(tabID: tabID, sql: nil))
            guard ready else { return }
            await self.ensureMentionColumns(AIMention.tokens(in: trimmed), tabID: tabID)
            self.appendUserMessage(tabID: tabID, content: trimmed)
            self.streamAssistantReply(tabID: tabID)
        }
    }

    func editAIMessage(tabID: UUID, messageID: UUID, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard document.openTabs.contains(where: { $0.id == tabID }) else { return }
        guard var thread = aiChatMessages[tabID],
              let idx = thread.firstIndex(where: { $0.id == messageID }),
              thread[idx].role == .user else { return }

        cancelAIExplain(tabID)
        thread[idx].content = trimmed
        thread = Array(thread.prefix(idx + 1))
        aiChatMessages[tabID] = thread
        aiError[tabID] = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ready = await self.ensureAIReady(for: tabID, pending: .explain(tabID: tabID, sql: nil))
            guard ready else { return }
            await self.ensureMentionColumns(AIMention.tokens(in: trimmed), tabID: tabID)
            self.streamAssistantReply(tabID: tabID)
        }
    }

    @discardableResult
    func insertSQLIntoActiveEditor(_ sql: String) -> Bool {
        let code = sql.trimmingCharacters(in: .newlines)
        guard !code.isEmpty else { return false }
        guard let tabID = selectedTabID else { return false }
        if let insert = activeEditorInsert, insert(tabID, code) {
            return true
        }
        let existing = tabTexts[tabID] ?? ""
        let next: String
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next = code
        } else if existing.hasSuffix("\n") {
            next = existing + "\n" + code
        } else {
            next = existing + "\n\n" + code
        }
        setTabTextExternal(tabID, sql: next)
        return true
    }

    func cancelAIExplain(_ tabID: UUID) {
        aiTasks[tabID]?.cancel()
        aiTasks[tabID] = nil
        aiStreamingTabs.remove(tabID)
    }

    func clearAIChat(_ tabID: UUID) {
        cancelAIExplain(tabID)
        aiChatMessages[tabID] = []
        aiError[tabID] = nil
    }

    func clearAIExplain(_ tabID: UUID) {
        clearAIChat(tabID)
    }

    func dismissAISetup() {
        showingAISetup = false
        aiSetupReason = nil
        pendingAIWork = nil
    }

    func completeAISetupAndRetry() {
        showingAISetup = false
        aiSetupReason = nil
        guard let pending = pendingAIWork else { return }
        pendingAIWork = nil
        switch pending {
        case .explain(let tabID, let sql):
            explainWithAI(tabID, sql: sql)
        case .generate(let tabID, let prompt):
            editorAIPrompt = prompt
            editorAIComposerVisible = true
            submitEditorAIGenerate(tabID: tabID)
        case .fix(let tabID, let sql, let error):
            fixSQLWithAI(tabID: tabID, sql: sql, error: error)
        case .ask(let tabID, let sql, let error):
            askAboutFailedSQL(tabID: tabID, sql: sql, error: error)
        }
    }

    @discardableResult
    func refreshOllamaModels(autoSelect: Bool = true) async -> Bool {
        isLoadingOllamaModels = true
        ollamaModelsError = nil
        defer { isLoadingOllamaModels = false }

        do {
            let client = OllamaClient(baseURLString: ollamaBaseURL)
            let models = try await client.listModels()
            ollamaModels = models.map(\.name).sorted()
            if ollamaModels.isEmpty {
                ollamaModelsError = "No models found. Run `ollama pull <model>` in Terminal."
                if autoSelect, !ollamaModel.isEmpty {
                    // Keep empty preferred; clear stale name only when auto-selecting.
                }
                return false
            }
            let current = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if autoSelect {
                if current.isEmpty || !ollamaModels.contains(current) {
                    ollamaModel = ollamaModels[0]
                }
            } else if !current.isEmpty && !ollamaModels.contains(current) {
                ollamaModelsError = "Model “\(current)” not installed. Available: \(ollamaModels.prefix(5).joined(separator: ", "))."
            }
            return true
        } catch {
            ollamaModels = []
            ollamaModelsError = error.localizedDescription
            return false
        }
    }

    // MARK: AI internals

    func ensureAIReady(for tabID: UUID, pending: PendingAIWork?) async -> Bool {
        if !aiEnabled {
            pendingAIWork = pending
            aiSetupReason = .disabled
            showingAISetup = true
            return false
        }

        let ok = await refreshOllamaModels(autoSelect: true)
        if !ok {
            pendingAIWork = pending
            if ollamaModelsError?.localizedCaseInsensitiveContains("reach") == true
                || ollamaModelsError?.localizedCaseInsensitiveContains("connect") == true
                || ollamaModelsError?.localizedCaseInsensitiveContains("Could not connect") == true
                || ollamaModelsError?.localizedCaseInsensitiveContains("Cannot reach") == true {
                aiSetupReason = .unreachable
            } else if ollamaModels.isEmpty {
                aiSetupReason = .noModels
            } else {
                aiSetupReason = .unreachable
            }
            showingAISetup = true
            return false
        }

        let modelName = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelName.isEmpty {
            pendingAIWork = pending
            aiSetupReason = ollamaModels.isEmpty ? .noModels : .noModelSelected
            showingAISetup = true
            return false
        }

        return true
    }

    func startExplainTurn(tabID: UUID, sql: String) {
        openAIPanel()
        aiError[tabID] = nil

        let dialect = document.connections
            .first(where: { $0.id == document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID })?
            .kind
        let user = SQLExplainPrompt.userMessage(sql: sql, dialect: dialect, schemaTables: schemaTablesForAI(tabID: tabID))
        appendUserMessage(tabID: tabID, content: user)
        streamAssistantReply(tabID: tabID)
    }

    func appendUserMessage(tabID: UUID, content: String) {
        var thread = aiChatMessages[tabID] ?? []
        thread.append(AIChatMessage(role: .user, content: content))
        aiChatMessages[tabID] = thread
    }

    func streamAssistantReply(tabID: UUID) {
        let modelName = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else { return }

        cancelAIExplain(tabID)
        aiError[tabID] = nil

        var thread = aiChatMessages[tabID] ?? []
        let assistantID = UUID()
        thread.append(AIChatMessage(id: assistantID, role: .assistant, content: ""))
        aiChatMessages[tabID] = thread
        aiStreamingTabs.insert(tabID)

        let history = thread
            .filter { $0.id != assistantID }
            .map { msg -> OllamaClient.ChatTurn in
                OllamaClient.ChatTurn(
                    role: msg.role == .user ? "user" : "assistant",
                    content: msg.role == .user ? self.expandedAIUserContent(msg.content, tabID: tabID) : msg.content
                )
            }
        let baseURL = ollamaBaseURL
        let system = SQLExplainPrompt.systemPrompt

        aiTasks[tabID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.aiStreamingTabs.remove(tabID)
                self.aiTasks[tabID] = nil
            }
            let client = OllamaClient(baseURLString: baseURL)
            do {
                try await client.chatStream(
                    model: modelName,
                    system: system,
                    messages: history
                ) { delta in
                    Task { @MainActor [weak self] in
                        self?.appendAIDelta(tabID: tabID, messageID: assistantID, delta: delta)
                    }
                }
            } catch is CancellationError {
                // Keep partial assistant text.
            } catch let error as OllamaClient.ClientError where error == .cancelled {
                // Keep partial assistant text.
            } catch {
                let message = error.localizedDescription
                let existing = self.aiChatMessages[tabID]?.first(where: { $0.id == assistantID })?.content ?? ""
                if existing.isEmpty {
                    self.aiError[tabID] = message
                    // Drop empty assistant bubble.
                    self.aiChatMessages[tabID] = (self.aiChatMessages[tabID] ?? []).filter { $0.id != assistantID }
                } else {
                    self.aiError[tabID] = "Stopped: \(message)"
                }
            }
        }
    }

    func toggleEditorAIComposer() {
        if editorAIBusy {
            cancelEditorAI()
            return
        }
        if editorAIComposerVisible {
            dismissEditorAIComposer()
        } else {
            beginEditorAIComposer()
        }
    }

    func beginEditorAIComposer() {
        guard let tabID = selectedTabID else { return }
        editorAIComposerVisible = true
        editorAIStatus = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.ensureAIReady(
                for: tabID,
                pending: .generate(tabID: tabID, prompt: self.editorAIPrompt)
            )
        }
    }

    func dismissEditorAIComposer() {
        if editorAIBusy {
            cancelEditorAI()
        }
        editorAIComposerVisible = false
        editorAIStatus = nil
    }

    func submitEditorAIGenerate(tabID: UUID? = nil) {
        let tabID = tabID ?? selectedTabID
        guard let tabID else { return }
        let prompt = editorAIPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ready = await self.ensureAIReady(
                for: tabID,
                pending: .generate(tabID: tabID, prompt: prompt)
            )
            guard ready else { return }
            let mentions = AIMention.tokens(in: prompt)
            await self.ensureMentionColumns(mentions, tabID: tabID)
            self.streamSQLIntoEditor(
                tabID: tabID,
                system: SQLGeneratePrompt.systemPrompt,
                user: SQLGeneratePrompt.userMessage(
                    prompt: prompt,
                    dialect: self.dialect(for: tabID),
                    schema: self.schemaContext(for: tabID, mentioned: mentions),
                    selectedSQL: self.activeSQLProvider?()
                ),
                status: "Generating…"
            )
        }
    }

    func fixSQLWithAI(tabID: UUID, sql: String, error: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ready = await self.ensureAIReady(
                for: tabID,
                pending: .fix(tabID: tabID, sql: sql, error: error)
            )
            guard ready else { return }
            let mentions = self.tableMentions(fromSQL: sql, tabID: tabID)
            await self.ensureMentionColumns(mentions, tabID: tabID)
            self.streamSQLIntoEditor(
                tabID: tabID,
                system: SQLFixPrompt.systemPrompt,
                user: SQLFixPrompt.userMessage(
                    sql: sql,
                    error: error,
                    dialect: self.dialect(for: tabID),
                    schema: self.schemaContext(for: tabID, mentioned: mentions)
                ),
                status: "Fixing…",
                replaceStatement: sql
            )
        }
    }

    func askAboutFailedSQL(tabID: UUID, sql: String, error: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ready = await self.ensureAIReady(
                for: tabID,
                pending: .ask(tabID: tabID, sql: sql, error: error)
            )
            guard ready else { return }
            self.openAIPanel()
            let mentions = self.tableMentions(fromSQL: sql, tabID: tabID)
            await self.ensureMentionColumns(mentions, tabID: tabID)
            let user = SQLFixPrompt.chatUserMessage(
                sql: sql,
                error: error,
                dialect: self.dialect(for: tabID),
                schema: self.schemaContext(for: tabID, mentioned: mentions)
            )
            self.appendUserMessage(tabID: tabID, content: user)
            self.streamAssistantReply(tabID: tabID)
        }
    }

    func cancelEditorAI() {
        editorAITask?.cancel()
        editorAITask = nil
        editorAIBusy = false
        editorAIStatus = nil
    }

    func streamSQLIntoEditor(
        tabID: UUID,
        system: String,
        user: String,
        status: String,
        replaceStatement: String? = nil
    ) {
        let modelName = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else { return }

        cancelEditorAI()
        editorAIBusy = true
        editorAIStatus = status
        editorAIRaw = ""

        var insertStart = 0
        var original = ""
        if let begun = editorAIInsert?(tabID, replaceStatement) {
            insertStart = begun.start
            original = begun.original
        }

        let baseURL = ollamaBaseURL
        let start = insertStart
        editorAITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.editorAIBusy = false
                self.editorAITask = nil
            }
            do {
                let client = OllamaClient(baseURLString: baseURL)
                try await client.chatStream(model: modelName, system: system, user: user) { delta in
                    Task { @MainActor [weak self] in
                        guard let self, self.editorAIBusy else { return }
                        self.editorAIRaw += delta
                        self.editorAIApply?(tabID, start, AIEditorSQL.stripped(self.editorAIRaw))
                    }
                }
                self.editorAIFinish?(tabID)
                self.editorAIStatus = nil
                self.editorAIComposerVisible = false
                self.editorAIPrompt = ""
            } catch is CancellationError {
                self.editorAICancelInsert?(tabID, insertStart, original)
                self.editorAIStatus = "Cancelled"
            } catch let error as OllamaClient.ClientError where error == .cancelled {
                self.editorAICancelInsert?(tabID, insertStart, original)
                self.editorAIStatus = "Cancelled"
            } catch {
                self.editorAICancelInsert?(tabID, insertStart, original)
                self.editorAIStatus = error.localizedDescription
            }
        }
    }

    func dialect(for tabID: UUID) -> DatabaseKind? {
        document.connections
            .first(where: { $0.id == document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID })?
            .kind
    }

    func schemaTablesForAI(tabID: UUID) -> [String] {
        let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID
            ?? selectedConnectionID
        if let profileID, let snap = schemaByProfile[profileID] {
            return snap.objects.map(\.displayName)
        }
        return schemaTables
    }

    func schemaContext(for tabID: UUID, mentioned: [AIMentionToken] = []) -> String {
        let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID
            ?? selectedConnectionID
        let objects = profileID.flatMap { schemaByProfile[$0]?.objects } ?? schemaObjects
        let columns = profileID.flatMap { schemaByProfile[$0]?.columns } ?? schemaColumnsByID
        if !mentioned.isEmpty {
            let focused = resolveMentionedObjects(mentioned, in: objects)
            let tables = focused.map { object in
                AIMentionTable(
                    displayName: object.displayName,
                    columns: (columns[object.id] ?? []).map {
                        AIMentionColumn(
                            name: $0.name,
                            dataType: $0.dataType,
                            isPrimaryKey: $0.isPrimaryKey,
                            isNullable: $0.isNullable
                        )
                    }
                )
            }
            return AIMention.formatTables(tables)
        }
        if objects.isEmpty {
            return "Schema: (none loaded)"
        }
        var lines = ["Schema:"]
        for object in objects.prefix(40) {
            let cols = (columns[object.id] ?? []).prefix(24).map(\.name).joined(separator: ", ")
            if cols.isEmpty {
                lines.append("- \(object.displayName)")
            } else {
                lines.append("- \(object.displayName) (\(cols))")
            }
        }
        if objects.count > 40 {
            lines.append("…and \(objects.count - 40) more tables")
        }
        return lines.joined(separator: "\n")
    }

    func aiMentionItems(prefix: String) -> [SQLCompletionItem] {
        let objects = schemaObjects(for: selectedTabID)
        let priority = Set(prioritizedTableNames().map { $0.lowercased() })
        let ranked = objects.compactMap { object -> (SchemaObject, Int)? in
            guard let rank = AIMention.matchRank(
                query: prefix,
                name: object.name,
                qualified: object.displayName,
                schema: object.schema
            ) else { return nil }
            let bump = priority.contains(object.name.lowercased()) ? -1 : 0
            return (object, rank + bump)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }
        return ranked.prefix(80).map { object, _ in
            SQLCompletionItem(
                kind: object.kind == .view ? .view : .table,
                label: object.name,
                insertText: mentionInsertText(for: object, in: objects),
                detail: object.schema
            )
        }
    }

    func aiValidatedMentionKeys() -> Set<String> {
        var keys = Set<String>()
        for object in schemaObjects(for: selectedTabID) {
            keys.insert(object.name.lowercased())
            keys.insert(object.displayName.lowercased())
        }
        return keys
    }

    func aiMentionEmptyMessage(prefix: String) -> String {
        if schemaObjects(for: selectedTabID).isEmpty {
            return "No tables loaded — connect and open Schema"
        }
        if prefix.isEmpty {
            return "Type to filter tables"
        }
        return "No tables match “\(prefix)”"
    }

    func prefetchMention(_ item: SQLCompletionItem) {
        ensureCompletionColumns(named: item.insertText)
    }

    func ensureMentionColumns(_ tokens: [AIMentionToken], tabID: UUID) async {
        let objects = schemaObjects(for: tabID)
        for object in resolveMentionedObjects(tokens, in: objects) {
            let profileID = document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID
                ?? selectedConnectionID
            let cached = profileID.flatMap { schemaByProfile[$0]?.columns[object.id] }
                ?? schemaColumnsByID[object.id]
            if cached == nil {
                await loadSchemaColumns(object, reportError: false, profileID: profileID)
            }
        }
    }

    func tableMentions(fromSQL sql: String, tabID: UUID) -> [AIMentionToken] {
        let objects = schemaObjects(for: tabID)
        guard !objects.isEmpty else { return [] }
        let tokens = SQLLexer().tokenize(sql)
        var names: [String] = []
        var i = 0
        while i < tokens.count {
            if tokens[i].kind == .identifier {
                if i + 2 < tokens.count,
                   tokens[i + 1].text == ".",
                   tokens[i + 2].kind == .identifier {
                    names.append("\(tokens[i].text).\(tokens[i + 2].text)")
                    i += 3
                    continue
                }
                names.append(tokens[i].text)
            }
            i += 1
        }
        var seen = Set<String>()
        var mentions: [AIMentionToken] = []
        for name in names {
            let token = AIMentionToken(schema: nil, name: name, utf16Range: 0..<0)
            let matches = resolveMentionedObjects([token], in: objects)
            for match in matches where seen.insert(match.id).inserted {
                mentions.append(
                    AIMentionToken(schema: match.schema, name: match.name, utf16Range: 0..<0)
                )
            }
        }
        return mentions
    }

    func expandedAIUserContent(_ text: String, tabID: UUID) -> String {
        let mentions = AIMention.tokens(in: text)
        guard !mentions.isEmpty else { return text }
        return text + "\n\n" + schemaContext(for: tabID, mentioned: mentions)
    }

    func schemaObjects(for tabID: UUID?) -> [SchemaObject] {
        let profileID = tabID.flatMap { id in
            document.openTabs.first(where: { $0.id == id })?.connectionProfileID
        } ?? selectedConnectionID
        let fromProfile = profileID.flatMap { schemaByProfile[$0]?.objects }
        if let fromProfile, !fromProfile.isEmpty { return fromProfile }
        return schemaObjects
    }

    func resolveMentionedObjects(_ tokens: [AIMentionToken], in objects: [SchemaObject]) -> [SchemaObject] {
        var seen = Set<String>()
        var result: [SchemaObject] = []
        for token in tokens {
            let matches = objects.filter { object in
                if let schema = token.schema, !schema.isEmpty {
                    return (object.schema?.caseInsensitiveCompare(schema) == .orderedSame
                        && object.name.caseInsensitiveCompare(token.name) == .orderedSame)
                        || object.displayName.caseInsensitiveCompare(token.raw) == .orderedSame
                }
                return object.name.caseInsensitiveCompare(token.name) == .orderedSame
                    || object.displayName.caseInsensitiveCompare(token.raw) == .orderedSame
                    || object.id.caseInsensitiveCompare(token.raw) == .orderedSame
            }
            for match in matches where seen.insert(match.id).inserted {
                result.append(match)
            }
        }
        return result
    }

    func mentionInsertText(for object: SchemaObject, in objects: [SchemaObject]) -> String {
        let ambiguous = objects.contains {
            $0.id != object.id && $0.name.caseInsensitiveCompare(object.name) == .orderedSame
        }
        if ambiguous { return object.displayName }
        return object.name
    }

    func appendAIDelta(tabID: UUID, messageID: UUID, delta: String) {
        guard var thread = aiChatMessages[tabID],
              let idx = thread.firstIndex(where: { $0.id == messageID }) else { return }
        thread[idx].content.append(delta)
        aiChatMessages[tabID] = thread
    }
}
