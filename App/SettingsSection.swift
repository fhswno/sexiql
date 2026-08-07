import Foundation

enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case appearance
    case workspace
    case layout
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .workspace: "Workspace"
        case .layout: "Layout defaults"
        case .ai: "AI / Ollama"
        }
    }
}
