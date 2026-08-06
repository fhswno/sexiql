import Foundation

struct AIChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable, Equatable {
        case user
        case assistant
    }

    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum AISetupReason: String, Identifiable, Sendable, Equatable {
    case disabled
    case unreachable
    case noModels
    case noModelSelected

    var id: String { rawValue }
}
