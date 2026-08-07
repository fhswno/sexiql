import Foundation

enum TabTitleDeriver {
    static func derive(from sql: String) -> String? {
        let collapsed = sql
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }

        let first = collapsed.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? collapsed
        guard !first.isEmpty else { return nil }

        let upper = first.uppercased()
        if let table = tableName(after: ["FROM", "INTO", "UPDATE", "TABLE", "VIEW"], in: first, upper: upper) {
            let verb: String
            if upper.hasPrefix("SELECT") || upper.hasPrefix("WITH") { verb = "" }
            else if upper.hasPrefix("INSERT") { verb = "INSERT " }
            else if upper.hasPrefix("UPDATE") { verb = "UPDATE " }
            else if upper.hasPrefix("DELETE") { verb = "DELETE " }
            else if upper.hasPrefix("CREATE") { verb = "CREATE " }
            else if upper.hasPrefix("DROP") { verb = "DROP " }
            else if upper.hasPrefix("ALTER") { verb = "ALTER " }
            else { verb = "" }
            let title = verb.isEmpty ? table : verb + table
            return String(title.prefix(40))
        }

        return String(first.prefix(36))
    }

    private static func tableName(after keywords: [String], in sql: String, upper: String) -> String? {
        for keyword in keywords {
            guard let range = upper.range(of: " \(keyword) ") ?? (upper.hasPrefix("\(keyword) ")
                ? upper.range(of: "\(keyword) ")
                : nil) else { continue }
            let after = sql[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !after.isEmpty else { continue }
            var token = ""
            for ch in after {
                if ch.isWhitespace || ch == "(" || ch == ";" || ch == "," { break }
                token.append(ch)
            }
            token = token
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[]"))
            if let dot = token.lastIndex(of: ".") {
                token = String(token[token.index(after: dot)...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[]"))
            }
            if !token.isEmpty { return token }
        }
        return nil
    }
}
