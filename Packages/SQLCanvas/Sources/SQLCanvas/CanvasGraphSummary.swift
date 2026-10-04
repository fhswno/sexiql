import Foundation

public enum CanvasGraphSummary {
    public static let defaultCharacterBudget = 12_000

    public static func build(
        tables: [CanvasTable],
        edges: [CanvasEdge],
        characterBudget: Int = defaultCharacterBudget
    ) -> String {
        let sortedTables = tables.sorted { $0.id < $1.id }
        let sortedEdges = edges.sorted { $0.id < $1.id }

        var output = render(sortedTables, sortedEdges, columnLimit: .all)
        if output.count > characterBudget {
            output = render(sortedTables, sortedEdges, columnLimit: .first(8))
        }
        if output.count > characterBudget {
            output = render(sortedTables, sortedEdges, columnLimit: .keysOnly)
        }
        if output.count > characterBudget {
            output = renderWithinBudget(sortedTables, sortedEdges, columnLimit: .keysOnly, budget: characterBudget)
        }
        return output
    }

    enum ColumnLimit {
        case all
        case first(Int)
        case keysOnly
    }

    private static func render(
        _ tables: [CanvasTable],
        _ edges: [CanvasEdge],
        columnLimit: ColumnLimit
    ) -> String {
        let included = Set(tables.map(\.id))
        var lines: [String] = ["TABLES:"]

        for table in tables {
            var columns = table.columns
            switch columnLimit {
            case .all:
                break
            case .first(let n):
                if columns.count > n {
                    let hidden = columns.count - n
                    columns = Array(columns.prefix(n)) + [
                        CanvasColumn(name: "+\(hidden) more columns", dataType: "", isNullable: false),
                    ]
                }
            case .keysOnly:
                let keys = columns.filter { $0.isPrimaryKey || $0.isForeignKey }
                if columns.count > keys.count {
                    columns = keys + [
                        CanvasColumn(name: "+\(columns.count - keys.count) more columns", dataType: "", isNullable: false),
                    ]
                }
            }
            let rendered = columns
                .map { column -> String in
                    var text = "\(column.name) \(column.dataType)".trimmingCharacters(in: .whitespaces)
                    if column.isPrimaryKey { text += " [PK]" }
                    if column.isForeignKey { text += " [FK]" }
                    return text
                }
                .joined(separator: ", ")
            lines.append("- \(table.name): \(rendered.isEmpty ? "(no columns)" : rendered)")
        }

        lines.append("")
        lines.append("RELATIONSHIPS (many-side -> one-side):")
        var relationshipCount = 0
        for edge in edges where included.contains(edge.fromTableID) && included.contains(edge.toTableID) {
            let fromTable = tables.first { $0.id == edge.fromTableID }
            let toTable = tables.first { $0.id == edge.toTableID }
            guard let fromName = fromTable?.name, let toName = toTable?.name else { continue }
            let marker = edge.isVirtual ? " [virtual — local annotation, not declared in the database]" : ""
            lines.append("- \(fromName).\(edge.fromColumn) -> \(toName).\(edge.toColumn) (N:1)\(marker)")
            relationshipCount += 1
        }
        if relationshipCount == 0 {
            lines.append("- (none declared)")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderWithinBudget(
        _ tables: [CanvasTable],
        _ edges: [CanvasEdge],
        columnLimit: ColumnLimit,
        budget: Int
    ) -> String {
        var kept = tables
        while kept.count > 1 {
            kept.removeLast()
            let output = render(kept, edges, columnLimit: columnLimit)
            if output.count <= budget {
                return output + "\n(schema truncated for brevity)"
            }
        }
        return render([tables.first].compactMap { $0 }, [], columnLimit: columnLimit)
    }
}
