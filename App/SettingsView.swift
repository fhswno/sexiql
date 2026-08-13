import SwiftUI
import SQLCore
import SQLUI

struct SettingsChrome: View {
    @Bindable var model: WorkspaceModel
    var preferredScheme: ColorScheme?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsView()
            .environment(model)
            .preferredColorScheme(preferredScheme)
            .tint(SexiQLColors.chromeTint(model.document.settings.tintName, scheme: colorScheme))
    }
}

struct SettingsView: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var filter = ""
    @State private var highlightedSection: SettingsSection?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search settings…", text: $filter)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.quaternary.opacity(0.35))
            Divider()
            Form {
                if showsSection(.appearance) {
                    Section {
                        Picker("Theme", selection: appearanceBinding) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Picker("Accent Color", selection: tintBinding) {
                            Text("System").tag(String?.none)
                            Text("Blue").tag(Optional("blue"))
                            Text("Orange").tag(Optional("orange"))
                            Text("Green").tag(Optional("green"))
                            Text("Purple").tag(Optional("purple"))
                        }
                        Toggle("Compact result grid", isOn: compactGridBinding)
                        Picker("Copy selected rows as", selection: copyFormatBinding) {
                            ForEach(CopySelectedRowsFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        Text("Used by ⌘C and row Copy. Toolbar still offers CSV and JSON.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        sectionHeader(.appearance)
                    }
                }
                if showsSection(.workspace) {
                    Section {
                        Toggle("Restore workspace on launch", isOn: restoreBinding)
                        Toggle("Confirm before disconnect", isOn: confirmBinding)
                    } header: {
                        sectionHeader(.workspace)
                    }
                }
                if showsSection(.layout) {
                    Section {
                        Toggle("Show sidebar", isOn: sidebarBinding)
                    } header: {
                        sectionHeader(.layout)
                    }
                }
                if showsSection(.ai) {
                    Section {
                        Toggle("Enable AI features", isOn: aiEnabledBinding)
                        TextField("Ollama URL", text: ollamaURLBinding)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            if model.ollamaModels.isEmpty {
                                TextField("Model", text: ollamaModelBinding, prompt: Text("No models yet"))
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Model", selection: ollamaModelBinding) {
                                    ForEach(model.ollamaModels, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                            }
                            Button {
                                Task { await model.refreshOllamaModels(autoSelect: true) }
                            } label: {
                                if model.isLoadingOllamaModels {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Refresh")
                                }
                            }
                            .disabled(!model.aiEnabled || model.isLoadingOllamaModels)
                        }
                        if let err = model.ollamaModelsError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Runs entirely on your Mac via Ollama. Install from ollama.com, pull any model, then Refresh — SexiQL uses the first installed model by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        sectionHeader(.ai)
                    }
                }
                if !filter.isEmpty
                    && !showsSection(.appearance)
                    && !showsSection(.workspace)
                    && !showsSection(.layout)
                    && !showsSection(.ai) {
                    Section {
                        Text("No settings match “\(filter)”.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            if let focus = model.settingsFocusSection {
                highlightedSection = focus
                filter = ""
                model.settingsFocusSection = nil
            }
            AppIconAppearance.apply(for: model.appearance)
            if model.aiEnabled {
                Task { await model.refreshOllamaModels() }
            }
        }
        .onChange(of: model.settingsFocusSection) { _, section in
            guard let section else { return }
            highlightedSection = section
            filter = ""
            model.settingsFocusSection = nil
        }
    }

    private func showsSection(_ section: SettingsSection) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return SettingsSearchIndex.items.contains { $0.section == section && $0.matches(q) }
    }

    private func sectionHeader(_ section: SettingsSection) -> some View {
        Text(section.title)
            .foregroundStyle(highlightedSection == section ? Color.accentColor : .secondary)
            .fontWeight(highlightedSection == section ? .semibold : .regular)
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { model.appearance },
            set: { model.appearance = $0 }
        )
    }

    private var tintBinding: Binding<String?> {
        Binding(
            get: { model.document.settings.tintName },
            set: {
                model.document.settings.tintName = $0
                model.saveWorkspace()
            }
        )
    }

    private var copyFormatBinding: Binding<CopySelectedRowsFormat> {
        Binding(
            get: { model.copySelectedRowsFormat },
            set: { model.copySelectedRowsFormat = $0 }
        )
    }

    private var compactGridBinding: Binding<Bool> {
        Binding(
            get: { model.document.settings.compactGrid },
            set: {
                model.document.settings.compactGrid = $0
                model.saveWorkspace()
            }
        )
    }

    private var restoreBinding: Binding<Bool> {
        Binding(
            get: { model.document.settings.autoRestoreWorkspace },
            set: {
                model.document.settings.autoRestoreWorkspace = $0
                model.saveWorkspace()
            }
        )
    }

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { model.document.settings.confirmBeforeDisconnect },
            set: {
                model.document.settings.confirmBeforeDisconnect = $0
                model.saveWorkspace()
            }
        )
    }

    private var sidebarBinding: Binding<Bool> {
        Binding(
            get: { model.sidebarVisible },
            set: { model.sidebarVisible = $0 }
        )
    }

    private var aiEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.aiEnabled },
            set: { model.aiEnabled = $0 }
        )
    }

    private var ollamaURLBinding: Binding<String> {
        Binding(
            get: { model.ollamaBaseURL },
            set: { model.ollamaBaseURL = $0 }
        )
    }

    private var ollamaModelBinding: Binding<String> {
        Binding(
            get: { model.ollamaModel },
            set: { model.ollamaModel = $0 }
        )
    }
}

