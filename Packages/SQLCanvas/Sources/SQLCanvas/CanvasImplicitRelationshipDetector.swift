import Foundation

public struct ImplicitCandidate: Sendable, Equatable, Identifiable {
    public var id: String
    public var fromTableID: String
    public var fromColumn: String
    public var toTableID: String
    public var toColumn: String
    public var matchedBy: String

    public init(
        fromTableID: String,
        fromColumn: String,
        toTableID: String,
        toColumn: String,
        matchedBy: String
    ) {
        self.id = "\(fromTableID).\(fromColumn)->\(toTableID).\(toColumn)"
        self.fromTableID = fromTableID
        self.fromColumn = fromColumn
        self.toTableID = toTableID
        self.toColumn = toColumn
        self.matchedBy = matchedBy
    }
}

public enum CanvasImplicitRelationshipDetector {
    public static func findCandidates(
        tables: [CanvasTable],
        existingEdges: [CanvasEdge]
    ) -> [ImplicitCandidate] {
        let declaredPairs = Set(existingEdges.map { "\(edgeKey($0.fromTableID, $0.fromColumn))|\(edgeKey($0.toTableID, $0.toColumn))" })

        var candidates: [ImplicitCandidate] = []
        var seen = Set<String>()

        for table in tables {
            for column in table.columns where !column.isPrimaryKey && !column.isForeignKey {
                guard let base = referenceBase(of: column.name) else { continue }
                guard let target = matchTable(base: base, tables: tables) else { continue }
                guard let targetPK = target.columns.first(where: { $0.isPrimaryKey })?.name
                    ?? target.columns.first(where: { $0.name == "id" })?.name else { continue }
                if !isTypeCompatible(column.dataType, targetColumnTypes: target.columns.filter { $0.isPrimaryKey }.map(\.dataType)) {
                    continue
                }

                let pairKey = "\(edgeKey(table.id, column.name))|\(edgeKey(target.id, targetPK))"
                if declaredPairs.contains(pairKey) { continue }
                guard seen.insert(pairKey).inserted else { continue }

                candidates.append(
                    ImplicitCandidate(
                        fromTableID: table.id,
                        fromColumn: column.name,
                        toTableID: target.id,
                        toColumn: targetPK,
                        matchedBy: "column \(column.name) references \(target.name)"
                    )
                )
            }
        }
        return candidates
    }

    // MARK: - Internals

    private static func edgeKey(_ tableID: String, _ column: String) -> String {
        "\(tableID).\(column)"
    }

    static func referenceBase(of columnName: String) -> String? {
        let lower = columnName.lowercased()
        for suffix in ["_id", "_key", "_ref", "_uuid"] {
            if lower.hasSuffix(suffix), lower.count > suffix.count + 1 {
                return String(lower.dropLast(suffix.count))
            }
        }
        return nil
    }

    static func matchTable(base: String, tables: [CanvasTable]) -> CanvasTable? {
        let candidates = tables
        if let exact = candidates.first(where: { normalized($0.name) == base }) {
            return exact
        }
        if let singular = candidates.first(where: { base == singularForm(of: $0.name) }) {
            return singular
        }
        if let plural = candidates.first(where: { normalized($0.name) == base + "s" || normalized($0.name) == base + "es" }) {
            return plural
        }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func singularForm(of name: String) -> String {
        let lower = normalized(name)
        if lower.hasSuffix("ies"), lower.count > 3 {
            return String(lower.dropLast(3)) + "y"
        }
        if lower.hasSuffix("ses"), lower.count > 3 {
            return String(lower.dropLast(2))
        }
        if lower.hasSuffix("s"), lower.count > 1 {
            return String(lower.dropLast(1))
        }
        return lower
    }

    static func isTypeCompatible(_ columnType: String, targetColumnTypes: [String]) -> Bool {
        guard !targetColumnTypes.isEmpty else { return true }
        let numericPrefixes = ["int", "smallint", "bigint", "numeric", "decimal", "double", "real", "float"]
        func isNumeric(_ type: String) -> Bool {
            numericPrefixes.contains { type.lowercased().hasPrefix($0) }
        }
        let columnNumeric = isNumeric(columnType)
        return targetColumnTypes.contains { isNumeric($0) == columnNumeric || $0.lowercased() == "uuid" }
    }
}
