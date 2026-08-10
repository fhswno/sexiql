import Foundation

public struct PGError: Error, LocalizedError, Sendable, Equatable {
    public var code: String
    public var message: String
    public var detail: String?
    public var hint: String?
    public var position: Int?

    public init(code: String, message: String, detail: String? = nil, hint: String? = nil, position: Int? = nil) {
        self.code = code
        self.message = message
        self.detail = detail
        self.hint = hint
        self.position = position
    }

    public var errorDescription: String? {
        var text = message
        if let detail, !detail.isEmpty { text += "\n\(detail)" }
        if let hint, !hint.isEmpty { text += "\nHint: \(hint)" }
        if !code.isEmpty, code != "08001", code != "08006" {
            text += " [\(code)]"
        }
        return text
    }
}
