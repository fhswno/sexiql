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
            let ready = await self.ensureAIReady(for: tabID, pendingSQL: overrideSQL)
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
            let ready = await self.ensureAIReady(for: tabID, pendingSQL: nil)
            guard ready else { return }
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
            let ready = await self.ensureAIReady(for: tabID, pendingSQL: nil)
            guard ready else { return }
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
        pendingAIExplain = nil
    }

    func completeAISetupAndRetry() {
        showingAISetup = false
        aiSetupReason = nil
        guard let pending = pendingAIExplain else { return }
        pendingAIExplain = nil
        explainWithAI(pending.tabID, sql: pending.sql)
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

    func ensureAIReady(for tabID: UUID, pendingSQL: String?) async -> Bool {
        if !aiEnabled {
            pendingAIExplain = (tabID, pendingSQL)
            aiSetupReason = .disabled
            showingAISetup = true
            return false
        }

        let ok = await refreshOllamaModels(autoSelect: true)
        if !ok {
            pendingAIExplain = (tabID, pendingSQL)
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
            pendingAIExplain = (tabID, pendingSQL)
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
        let user = SQLExplainPrompt.userMessage(sql: sql, dialect: dialect, schemaTables: schemaTables)
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
                    content: msg.content
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

    func appendAIDelta(tabID: UUID, messageID: UUID, delta: String) {
        guard var thread = aiChatMessages[tabID],
              let idx = thread.firstIndex(where: { $0.id == messageID }) else { return }
        thread[idx].content.append(delta)
        aiChatMessages[tabID] = thread
    }
}
