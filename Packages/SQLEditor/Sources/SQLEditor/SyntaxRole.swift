import Foundation

public enum SyntaxRole: Sendable, Equatable {
    case keyword
    case string
    case number
    case comment
    case identifier
    case parameter
    case other
}

public enum SyntaxRoleMapping: Sendable {
    public static func role(for kind: SQLTokenKind) -> SyntaxRole {
        switch kind {
        case .keyword: .keyword
        case .string: .string
        case .number: .number
        case .comment: .comment
        case .identifier: .identifier
        case .parameter: .parameter
        case .operator, .punctuation, .whitespace: .other
        }
    }
}
