import Foundation
import SQLCore

enum SQLGeneratePrompt {
    static let systemPrompt = """
    You are a senior SQL engineer inside SexiQL, a native macOS database client.
    Write correct SQL for the user's request.
    Output ONLY SQL. No markdown fences, no commentary, no preamble.
    Match the stated dialect. Use the provided schema when relevant.
    When mentioned tables include full column lists, prefer those tables.
    Do not invent tables or columns that are not in the schema unless the user asked to create them.
    """

    static func userMessage(
        prompt: String,
        dialect: DatabaseKind?,
        schema: String,
        selectedSQL: String?
    ) -> String {
        var parts: [String] = []
        parts.append("Dialect: \(dialect?.displayName ?? "unknown")")
        parts.append(schema)
        if let selectedSQL, !selectedSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Selected SQL:\n\(selectedSQL)")
        }
        parts.append("Request:\n\(prompt)")
        return parts.joined(separator: "\n\n")
    }
}

enum SQLFixPrompt {
    static let systemPrompt = """
    You are a senior SQL engineer inside SexiQL.
    Fix the failed SQL so it runs on the given dialect.
    Output ONLY the corrected SQL statement(s). No markdown fences, no commentary.
    Keep the user's intent. Use the schema when relevant. Prefer mentioned tables. Do not invent objects.
    """

    static func userMessage(
        sql: String,
        error: String,
        dialect: DatabaseKind?,
        schema: String
    ) -> String {
        """
        Dialect: \(dialect?.displayName ?? "unknown")

        \(schema)

        Failed SQL:
        \(sql)

        Error:
        \(error)

        Return the fixed SQL only.
        """
    }

    static func chatUserMessage(sql: String, error: String, dialect: DatabaseKind?, schema: String) -> String {
        """
        This query failed. Help me understand and fix it.

        Dialect: \(dialect?.displayName ?? "unknown")

        \(schema)

        SQL:
        ```sql
        \(sql)
        ```

        Error:
        \(error)
        """
    }
}

enum AIEditorSQL {
    static func stripped(_ raw: String) -> String {
        var text = raw
        if text.hasPrefix("```") {
            if let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            } else {
                return ""
            }
            if let fence = text.range(of: "```") {
                text = String(text[..<fence.lowerBound])
            }
        }
        return text
    }
}
