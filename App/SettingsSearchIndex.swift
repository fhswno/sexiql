import Foundation

enum SettingsSearchIndex {
    static let items: [SettingsSearchItem] = appearance + workspace + layout + ai

    static func matches(for query: String) -> [SettingsSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return items }
        return items.filter { $0.matches(trimmed) }
    }

    // MARK: - Catalog by Section

    private static let appearance: [SettingsSearchItem] = [
        item(
            id: "theme",
            title: "Theme",
            subtitle: "System, Light, or Dark appearance",
            keywords: ["theme", "appearance", "light", "dark", "system", "mode", "color scheme"],
            section: .appearance
        ),
        item(
            id: "tint",
            title: "Accent Color",
            subtitle: "Blue, orange, green, purple, or system",
            keywords: ["tint", "accent", "chrome", "color", "blue", "orange", "green", "purple"],
            section: .appearance
        ),
        item(
            id: "compact-grid",
            title: "Compact result grid",
            subtitle: "Denser rows in query results",
            keywords: ["compact", "grid", "density", "rows", "results"],
            section: .appearance
        ),
        item(
            id: "copy-selected-rows",
            title: "Copy selected rows as",
            subtitle: "Default format for ⌘C and row Copy (TSV, CSV, or JSON)",
            keywords: ["copy", "tsv", "csv", "json", "clipboard", "selected", "rows", "paste"],
            section: .appearance
        ),
    ]

    private static let workspace: [SettingsSearchItem] = [
        item(
            id: "restore",
            title: "Restore workspace on launch",
            subtitle: "Reopen tabs and connections",
            keywords: ["restore", "workspace", "launch", "reopen", "session"],
            section: .workspace
        ),
        item(
            id: "disconnect",
            title: "Confirm before disconnect",
            subtitle: "Ask before closing a live connection",
            keywords: ["disconnect", "confirm", "connection", "close"],
            section: .workspace
        ),
    ]

    private static let layout: [SettingsSearchItem] = [
        item(
            id: "sidebar",
            title: "Show sidebar",
            subtitle: "Default visibility for the left sidebar",
            keywords: ["sidebar", "navigator", "connections", "schema", "panel"],
            section: .layout
        ),
    ]

    private static let ai: [SettingsSearchItem] = [
        item(
            id: "ai-enable",
            title: "Enable AI features",
            subtitle: "Local Ollama explanations for SQL",
            keywords: ["ai", "ollama", "llm", "explain", "local", "model"],
            section: .ai
        ),
        item(
            id: "ollama-url",
            title: "Ollama URL",
            subtitle: "Base URL for the local Ollama server",
            keywords: ["ollama", "url", "host", "11434", "endpoint"],
            section: .ai
        ),
        item(
            id: "ollama-model",
            title: "Ollama model",
            subtitle: "Local model from ollama ls (first installed by default)",
            keywords: ["model", "llama", "mistral", "qwen", "pull"],
            section: .ai
        ),
    ]

    private static func item(
        id: String,
        title: String,
        subtitle: String,
        keywords: [String],
        section: SettingsSection
    ) -> SettingsSearchItem {
        SettingsSearchItem(
            id: id,
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            section: section
        )
    }
}
