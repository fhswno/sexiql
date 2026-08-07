import SwiftUI
import SQLUI

struct AISetupSheet: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var isChecking = false
    @State private var localError: String?

    private var reason: AISetupReason {
        model.aiSetupReason ?? .disabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SexiQLSpace.xl) {
            HStack(spacing: SexiQLSpace.sm) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up AI")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(SexiQLType.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                switch reason {
                case .disabled:
                    disabledBody
                case .unreachable:
                    unreachableBody
                case .noModels:
                    noModelsBody
                case .noModelSelected:
                    modelPickBody
                }
            }

            if let localError, !localError.isEmpty {
                Text(localError)
                    .font(SexiQLType.rowSubtitle)
                    .foregroundStyle(SexiQLColors.failed)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let err = model.ollamaModelsError, reason != .disabled {
                Text(err)
                    .font(SexiQLType.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Open Settings…") {
                    model.dismissAISetup()
                    model.openSettings(focus: .ai)
                }
                .keyboardShortcut("o", modifiers: .command)
                Spacer()
                Button("Cancel") {
                    model.dismissAISetup()
                }
                .keyboardShortcut(.cancelAction)
                primaryButton
            }
        }
        .padding(SexiQLSpace.xxl)
        .frame(width: 440)
        .onAppear {
            if reason != .disabled {
                Task { await refresh() }
            }
        }
    }

    private var subtitle: String {
        switch reason {
        case .disabled:
            return "AI features are off. Enable local Ollama to explain SQL."
        case .unreachable:
            return "SexiQL can’t reach Ollama on this Mac."
        case .noModels:
            return "Ollama is running but no models are installed."
        case .noModelSelected:
            return "Pick a local model to continue."
        }
    }

    @ViewBuilder
    private var disabledBody: some View {
        Toggle("Enable AI features", isOn: Binding(
            get: { model.aiEnabled },
            set: { model.aiEnabled = $0 }
        ))
        TextField("Ollama URL", text: Binding(
            get: { model.ollamaBaseURL },
            set: { model.ollamaBaseURL = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        Text("Install Ollama from ollama.com if needed, then pull any model you like.")
            .font(SexiQLType.rowSubtitle)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var unreachableBody: some View {
        TextField("Ollama URL", text: Binding(
            get: { model.ollamaBaseURL },
            set: { model.ollamaBaseURL = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        Text("Start the Ollama app (or `ollama serve`), then try again.")
            .font(SexiQLType.rowSubtitle)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var noModelsBody: some View {
        Text("In Terminal, pull a model — for example:")
            .font(SexiQLType.rowSubtitle)
        Text("ollama pull llama3.2")
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(SexiQLSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        Text("Any model works. SexiQL will use the first installed model by default.")
            .font(SexiQLType.rowSubtitle)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var modelPickBody: some View {
        if model.ollamaModels.isEmpty {
            Text("No models listed yet. Refresh after pulling one.")
                .font(SexiQLType.rowSubtitle)
                .foregroundStyle(.secondary)
        } else {
            Picker("Model", selection: Binding(
                get: { model.ollamaModel },
                set: { model.ollamaModel = $0 }
            )) {
                ForEach(model.ollamaModels, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        Button {
            Task { await primaryAction() }
        } label: {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 80)
            } else {
                Text(primaryTitle)
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isChecking || !canContinue)
        .buttonStyle(.borderedProminent)
    }

    private var primaryTitle: String {
        switch reason {
        case .disabled: "Enable & Continue"
        case .unreachable, .noModels: "Check Again"
        case .noModelSelected: "Continue"
        }
    }

    private var canContinue: Bool {
        switch reason {
        case .disabled:
            return model.aiEnabled
        case .unreachable, .noModels:
            return true
        case .noModelSelected:
            return !model.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !model.ollamaModels.isEmpty
        }
    }

    private func refresh() async {
        isChecking = true
        localError = nil
        defer { isChecking = false }
        _ = await model.refreshOllamaModels(autoSelect: true)
    }

    private func primaryAction() async {
        isChecking = true
        localError = nil
        defer { isChecking = false }

        if reason == .disabled {
            model.aiEnabled = true
        }

        let ok = await model.refreshOllamaModels(autoSelect: true)
        if !ok {
            if model.ollamaModels.isEmpty,
               let err = model.ollamaModelsError,
               err.localizedCaseInsensitiveContains("No models") {
                model.aiSetupReason = .noModels
            } else {
                model.aiSetupReason = .unreachable
            }
            localError = model.ollamaModelsError
            return
        }

        let name = model.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            if model.ollamaModels.isEmpty {
                model.aiSetupReason = .noModels
            } else {
                model.ollamaModel = model.ollamaModels[0]
            }
        }

        let finalName = model.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalName.isEmpty else {
            model.aiSetupReason = .noModels
            return
        }

        model.completeAISetupAndRetry()
    }
}
