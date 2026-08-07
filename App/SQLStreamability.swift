import Foundation
import SQLDrivers

enum SQLStreamability {
    static func isStreamable(_ sql: String) -> Bool {
        let head = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for prefix in ["SELECT", "WITH", "SHOW", "EXPLAIN", "VALUES", "PRAGMA", "TABLE ", "DESCRIBE", "EXECUTE"] {
            if head.hasPrefix(prefix) { return true }
        }
        return false
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let driver = error as? SQLDriverError, driver == .cancelled { return true }
        if let pg = error as? PGError, pg.code == "57014" { return true }
        let text = error.localizedDescription.lowercased()
        return text.contains("cancel") || text.contains("interrupt")
    }
}
