import Foundation
import SQLCore

enum SQLExplainPrompt {
    static let systemPrompt = """
    You are a senior SQL tutor inside SexiQL, a native macOS database client.
    Explain clearly what the given SQL does in plain language.
    Mention tables, filters, joins, aggregates, and side effects (INSERT/UPDATE/DELETE) when relevant.
    Do not invent indexes, data, or database features that are not implied by the SQL or schema list.
    If something is ambiguous, say so briefly.
    Prefer short paragraphs and bullet points. No preamble like "Sure!" or "Here's an explanation".
    """

    static func userMessage(
        sql: String,
        dialect: DatabaseKind?,
        schemaTables: [String]
    ) -> String {
        var parts: [String] = []

        if let dialect {
            parts.append("Dialect: \(dialect.displayName)")
        } else {
            parts.append("Dialect: unknown")
        }

        if schemaTables.isEmpty {
            parts.append("Schema tables: (none loaded)")
        } else {
            let limited = schemaTables.prefix(80)
            var schema = "Schema tables (\(schemaTables.count)):\n"
            for name in limited {
                schema += "- \(name)\n"
            }
            if schemaTables.count > limited.count {
                schema += "…and \(schemaTables.count - limited.count) more"
            }
            parts.append(schema.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        parts.append("SQL:\n```sql\n\(sql.trimmingCharacters(in: .whitespacesAndNewlines))\n```")
        parts.append("Explain what this SQL does.")
        return parts.joined(separator: "\n\n")
    }
}
