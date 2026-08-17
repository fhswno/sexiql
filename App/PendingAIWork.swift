import Foundation

enum PendingAIWork: Equatable {
    case explain(tabID: UUID, sql: String?)
    case generate(tabID: UUID, prompt: String)
    case fix(tabID: UUID, sql: String, error: String)
    case ask(tabID: UUID, sql: String, error: String)
}
