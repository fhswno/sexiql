import Foundation

public struct ExplainNode: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var nodeType: String
    public var relation: String?
    public var startupCost: Double?
    public var totalCost: Double?
    public var planRows: Double?
    public var planWidth: Double?
    public var actualStartupTime: Double?
    public var actualTotalTime: Double?
    public var actualRows: Double?
    public var detail: [String: String]
    public var children: [ExplainNode]

    public init(
        id: UUID = UUID(),
        nodeType: String,
        relation: String? = nil,
        startupCost: Double? = nil,
        totalCost: Double? = nil,
        planRows: Double? = nil,
        planWidth: Double? = nil,
        actualStartupTime: Double? = nil,
        actualTotalTime: Double? = nil,
        actualRows: Double? = nil,
        detail: [String: String] = [:],
        children: [ExplainNode] = []
    ) {
        self.id = id
        self.nodeType = nodeType
        self.relation = relation
        self.startupCost = startupCost
        self.totalCost = totalCost
        self.planRows = planRows
        self.planWidth = planWidth
        self.actualStartupTime = actualStartupTime
        self.actualTotalTime = actualTotalTime
        self.actualRows = actualRows
        self.detail = detail
        self.children = children
    }
}

public enum ExplainFormat: String, Codable, Sendable {
    case text
    case json
}


public struct SQLiteExplainRow: Sendable, Equatable {
    public var id: Int
    public var parentID: Int
    public var notUsed: Int
    public var detail: String

    public init(id: Int, parentID: Int, detail: String, notUsed: Int = 0) {
        self.id = id
        self.parentID = parentID
        self.notUsed = notUsed
        self.detail = detail
    }

    public init(id: Int, parent: Int, detail: String, notUsed: Int = 0) {
        self.init(id: id, parentID: parent, detail: detail, notUsed: notUsed)
    }

    public var parent: Int { parentID }
}

public struct ExplainParser: Sendable {
    public init() {}

    public func parse(jsonData: Data) throws -> ExplainNode? {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
        } catch {
            throw ExplainError.malformedJSON
        }

        guard let results = object as? [Any] else {
            throw ExplainError.invalidJSONStructure
        }
        guard let result = results.first else { return nil }
        guard let resultObject = result as? [String: Any] else {
            throw ExplainError.invalidJSONStructure
        }
        guard let planValue = resultObject["Plan"] else {
            throw ExplainError.missingPlan
        }
        guard let plan = planValue as? [String: Any] else {
            throw ExplainError.invalidNodeValue(key: "Plan")
        }
        return try Self.makePostgresNode(from: plan)
    }

    public func parse(mysqlJSONData: Data) throws -> ExplainNode? {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: mysqlJSONData, options: [.fragmentsAllowed])
        } catch {
            throw ExplainError.malformedJSON
        }
        guard let dictionary = object as? [String: Any] else {
            throw ExplainError.invalidJSONStructure
        }
        guard let queryBlock = dictionary["query_block"] as? [String: Any] else {
            throw ExplainError.missingPlan
        }
        return try Self.makeMySQLNode(from: queryBlock, label: "Query Block")
    }

    public func parse(sqliteText: String) throws -> ExplainNode? {
        var entries: [SQLiteTextEntry] = []

        for (offset, rawLine) in sqliteText.components(separatedBy: .newlines).enumerated() {
            guard !rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.caseInsensitiveCompare("QUERY PLAN") == .orderedSame {
                continue
            }
            if trimmed.caseInsensitiveCompare("id|parent|notused|detail") == .orderedSame {
                continue
            }

            guard let parsed = Self.parseSQLiteTextLine(rawLine) else {
                throw ExplainError.invalidSQLiteText(
                    line: offset + 1,
                    message: "could not read a plan detail"
                )
            }
            entries.append(SQLiteTextEntry(line: offset + 1, depth: parsed.depth, detail: parsed.detail))
        }

        guard !entries.isEmpty else { return nil }

        var rows: [SQLiteExplainRow] = []
        rows.reserveCapacity(entries.count)
        var stack: [(depth: Int, id: Int)] = []
        var nextID = 1
        var previousDepth: Int?

        for entry in entries {
            if let previousDepth, entry.depth > previousDepth + 1 {
                throw ExplainError.invalidSQLiteText(
                    line: entry.line,
                    message: "plan indentation skips a level"
                )
            }

            while let last = stack.last, last.depth >= entry.depth {
                stack.removeLast()
            }
            let parentID = stack.last?.id ?? 0
            rows.append(SQLiteExplainRow(id: nextID, parentID: parentID, detail: entry.detail))
            stack.append((depth: entry.depth, id: nextID))
            nextID += 1
            previousDepth = entry.depth
        }

        return try Self.makeSQLitePlan(from: rows)
    }

    public func parse(sqliteRows rows: [[String]]) throws -> ExplainNode? {
        var parsedRows: [SQLiteExplainRow] = []
        parsedRows.reserveCapacity(rows.count)

        for (index, row) in rows.enumerated() {
            if index == 0, Self.isSQLiteRowHeader(row) {
                continue
            }
            guard row.count == 3 || row.count >= 4 else {
                throw ExplainError.invalidSQLiteRow(
                    index: index,
                    message: "expected id, parent, detail or id, parent, notused, detail"
                )
            }

            let idIndex = row.startIndex
            let parentIndex = row.index(after: idIndex)
            let detailIndex = row.count == 3 ? row.index(row.startIndex, offsetBy: 2) : row.index(row.startIndex, offsetBy: 3)
            guard let id = Int(row[idIndex].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let parent = Int(row[parentIndex].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ExplainError.invalidSQLiteRow(index: index, message: "id and parent must be integers")
            }

            let notUsed: Int
            if row.count == 3 {
                notUsed = 0
            } else if let value = Int(row[row.index(row.startIndex, offsetBy: 2)].trimmingCharacters(in: .whitespacesAndNewlines)) {
                notUsed = value
            } else {
                throw ExplainError.invalidSQLiteRow(index: index, message: "notused must be an integer")
            }

            let detail = row[detailIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else {
                throw ExplainError.invalidSQLiteRow(index: index, message: "detail must not be empty")
            }
            parsedRows.append(SQLiteExplainRow(id: id, parentID: parent, detail: detail, notUsed: notUsed))
        }

        return try Self.makeSQLitePlan(from: parsedRows)
    }

    public func parse(sqliteRows rows: [SQLiteExplainRow]) throws -> ExplainNode? {
        try Self.makeSQLitePlan(from: rows)
    }
    
    public func parse(text: String) throws -> ExplainNode? {
        try parse(sqliteText: text)
    }

    private struct SQLiteTextEntry {
        let line: Int
        let depth: Int
        let detail: String
    }

    private static func makePostgresNode(from object: [String: Any]) throws -> ExplainNode {
        guard let nodeTypeValue = object["Node Type"] else {
            throw ExplainError.missingNodeType
        }
        guard let nodeType = nodeTypeValue as? String,
              !nodeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExplainError.invalidNodeValue(key: "Node Type")
        }

        let relation = try optionalString(object["Relation Name"], key: "Relation Name")
        let startupCost = try optionalNumber(object["Startup Cost"], key: "Startup Cost")
        let totalCost = try optionalNumber(object["Total Cost"], key: "Total Cost")
        let planRows = try optionalNumber(object["Plan Rows"], key: "Plan Rows")
        let planWidth = try optionalNumber(object["Plan Width"], key: "Plan Width")
        let actualStartupTime = try optionalNumber(object["Actual Startup Time"], key: "Actual Startup Time")
        let actualTotalTime = try optionalNumber(object["Actual Total Time"], key: "Actual Total Time")
        let actualRows = try optionalNumber(object["Actual Rows"], key: "Actual Rows")

        let children: [ExplainNode]
        if let plansValue = object["Plans"] {
            guard let plans = plansValue as? [Any] else {
                throw ExplainError.invalidNodeValue(key: "Plans")
            }
            var parsedChildren: [ExplainNode] = []
            parsedChildren.reserveCapacity(plans.count)
            for (index, value) in plans.enumerated() {
                guard let child = value as? [String: Any] else {
                    throw ExplainError.invalidNodeValue(key: "Plans[\(index)]")
                }
                parsedChildren.append(try makePostgresNode(from: child))
            }
            children = parsedChildren
        } else {
            children = []
        }

        let mappedKeys: Set<String> = [
            "Node Type", "Relation Name", "Startup Cost", "Total Cost",
            "Plan Rows", "Plan Width", "Actual Startup Time",
            "Actual Total Time", "Actual Rows", "Plans",
        ]
        var detail: [String: String] = [:]
        for (key, value) in object where !mappedKeys.contains(key) {
            detail[key] = detailString(value)
        }

        return ExplainNode(
            nodeType: nodeType,
            relation: relation,
            startupCost: startupCost,
            totalCost: totalCost,
            planRows: planRows,
            planWidth: planWidth,
            actualStartupTime: actualStartupTime,
            actualTotalTime: actualTotalTime,
            actualRows: actualRows,
            detail: detail,
            children: children
        )
    }

    private static func makeMySQLNode(from object: [String: Any], label: String) throws -> ExplainNode {
        var children: [ExplainNode] = []
        var relation: String?
        var nodeType = label
        var planRows: Double?
        var totalCost: Double?
        var detail: [String: String] = [:]

        if let table = object["table"] as? [String: Any] {
            if label == "Query Block" {
                children.append(try makeMySQLNode(from: table, label: (table["access_type"] as? String) ?? "Table"))
            } else {
                relation = table["table_name"] as? String
                nodeType = (table["access_type"] as? String) ?? "Table"
                planRows = number(table["rows_examined_per_scan"] ?? table["rows_produced_per_join"])
                totalCost = number((table["cost_info"] as? [String: Any])?["read_cost"])
                detail = detailDictionary(table)
            }
        } else if let tableName = object["table_name"] as? String {
            relation = tableName
            planRows = number(object["rows_examined_per_scan"] ?? object["rows_produced_per_join"])
            totalCost = number((object["cost_info"] as? [String: Any])?["read_cost"])
            detail = detailDictionary(object)
        }

        for (key, value) in object {
            if key == "table" || key == "cost_info" || key == "query_cost" { continue }
            if let array = value as? [[String: Any]] {
                for item in array {
                    children.append(try makeMySQLNode(from: item, label: displayLabel(key)))
                }
            } else if let child = value as? [String: Any], key != "cost_info" {
                children.append(try makeMySQLNode(from: child, label: displayLabel(key)))
            } else if !["select_id", "access_type", "table_name", "rows_examined_per_scan", "rows_produced_per_join"].contains(key) {
                detail[key] = detailString(value)
            }
        }

        return ExplainNode(
            nodeType: nodeType,
            relation: relation,
            totalCost: totalCost,
            planRows: planRows,
            detail: detail,
            children: children
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func detailDictionary(_ object: [String: Any]) -> [String: String] {
        let omitted: Set<String> = [
            "table_name", "access_type", "rows_examined_per_scan", "rows_produced_per_join",
            "cost_info", "table"]
        return object.reduce(into: [:]) { result, pair in
            guard !omitted.contains(pair.key) else { return }
            result[pair.key] = detailString(pair.value)
        }
    }

    private static func displayLabel(_ key: String) -> String {
        key.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    private static func optionalString(_ value: Any?, key: String) throws -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String else {
            throw ExplainError.invalidNodeValue(key: key)
        }
        return string
    }

    private static func optionalNumber(_ value: Any?, key: String) throws -> Double? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw ExplainError.invalidNodeValue(key: key)
        }
        let result = number.doubleValue
        guard result.isFinite else {
            throw ExplainError.invalidNodeValue(key: key)
        }
        return result
    }

    private static func detailString(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let string = value as? String { return string }
        if let boolean = value as? Bool { return boolean ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func parseSQLiteTextLine(_ rawLine: String) -> (depth: Int, detail: String)? {
        var line = rawLine
        while line.last?.isWhitespace == true {
            line.removeLast()
        }
        guard !line.isEmpty else { return nil }

        var candidate = line
        var depth = 0
        while true {
            if candidate.hasPrefix("|--") || candidate.hasPrefix("`--") || candidate.hasPrefix("+--") {
                let detail = String(candidate.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty ? nil : (depth, detail)
            }
            if candidate.hasPrefix("|  ") || candidate.hasPrefix("   ") {
                candidate = String(candidate.dropFirst(3))
                depth += 1
                continue
            }
            break
        }

        let detail = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? nil : (0, detail)
    }

    private static func isSQLiteRowHeader(_ row: [String]) -> Bool {
        guard row.count >= 4 else { return false }
        return row[0].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("id") == .orderedSame
            && row[1].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("parent") == .orderedSame
            && row[3].trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("detail") == .orderedSame
    }

    private static func makeSQLitePlan(from rows: [SQLiteExplainRow]) throws -> ExplainNode? {
        guard !rows.isEmpty else { return nil }

        var ids = Set<Int>()
        for row in rows {
            guard ids.insert(row.id).inserted else {
                throw ExplainError.invalidSQLiteTree(message: "duplicate node id \(row.id)")
            }
            guard !row.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ExplainError.invalidSQLiteTree(message: "node \(row.id) has empty detail")
            }
        }

        for row in rows where row.parentID > 0 && !ids.contains(row.parentID) {
            throw ExplainError.invalidSQLiteTree(
                message: "node \(row.id) refers to missing parent \(row.parentID)"
            )
        }

        var childrenByParent: [Int: [SQLiteExplainRow]] = [:]
        for row in rows where row.parentID > 0 {
            childrenByParent[row.parentID, default: []].append(row)
        }
        let roots = rows.filter { $0.parentID <= 0 }
        guard !roots.isEmpty else {
            throw ExplainError.invalidSQLiteTree(message: "plan contains no root node")
        }

        var visited = Set<Int>()
        func makeNode(_ row: SQLiteExplainRow, path: Set<Int>) throws -> ExplainNode {
            guard !path.contains(row.id) else {
                throw ExplainError.invalidSQLiteTree(message: "plan contains a cycle at node \(row.id)")
            }
            var nextPath = path
            nextPath.insert(row.id)
            var children: [ExplainNode] = []
            for child in childrenByParent[row.id, default: []] {
                children.append(try makeNode(child, path: nextPath))
            }
            visited.insert(row.id)
            return Self.makeSQLiteNode(from: row.detail, children: children)
        }

        var parsedRoots: [ExplainNode] = []
        parsedRoots.reserveCapacity(roots.count)
        for root in roots {
            parsedRoots.append(try makeNode(root, path: []))
        }
        if visited.count != rows.count {
            throw ExplainError.invalidSQLiteTree(message: "plan contains a cycle or disconnected node")
        }

        if parsedRoots.count == 1 {
            return parsedRoots[0]
        }
        return ExplainNode(nodeType: "QUERY PLAN", children: parsedRoots)
    }

    private static func makeSQLiteNode(from detail: String, children: [ExplainNode]) -> ExplainNode {
        let parsed = sqliteOperation(from: detail)
        return ExplainNode(
            nodeType: parsed.nodeType,
            relation: parsed.relation,
            detail: ["Detail": detail],
            children: children
        )
    }

    private static func sqliteOperation(from detail: String) -> (nodeType: String, relation: String?) {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["SCAN ", "SEARCH "] where trimmed.hasPrefix(prefix) {
            let remainder = String(trimmed.dropFirst(prefix.count))
            let relation = remainder.components(separatedBy: " USING ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(prefix.dropLast()), relation?.isEmpty == true ? nil : relation)
        }

        if trimmed.hasPrefix("BLOOM FILTER ON ") {
            let remainder = String(trimmed.dropFirst("BLOOM FILTER ON ".count))
            let relation = remainder.components(separatedBy: " ").first
            return ("BLOOM FILTER", relation?.isEmpty == true ? nil : relation)
        }

        if trimmed.hasPrefix("USE TEMP B-TREE") {
            return ("USE TEMP B-TREE", nil)
        }
        if trimmed.hasPrefix("CORRELATED SCALAR SUBQUERY") {
            return ("CORRELATED SCALAR SUBQUERY", nil)
        }
        if trimmed.hasPrefix("CO-ROUTINE ") {
            let remainder = String(trimmed.dropFirst("CO-ROUTINE ".count))
            return ("CO-ROUTINE", remainder.isEmpty ? nil : remainder)
        }
        if trimmed.hasPrefix("MATERIALIZE ") {
            let remainder = String(trimmed.dropFirst("MATERIALIZE ".count))
            return ("MATERIALIZE", remainder.isEmpty ? nil : remainder)
        }
        if trimmed.hasPrefix("COMPOUND QUERY") {
            return ("COMPOUND QUERY", nil)
        }
        if trimmed.hasPrefix("LEFT-MOST SUBQUERY") {
            return ("LEFT-MOST SUBQUERY", nil)
        }

        let nodeType = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        return (nodeType, nil)
    }
}

public enum ExplainError: Error, Sendable, Equatable {
    case notImplemented
    case malformedJSON
    case invalidJSONStructure
    case missingPlan
    case missingNodeType
    case invalidNodeValue(key: String)
    case invalidSQLiteText(line: Int, message: String)
    case invalidSQLiteRow(index: Int, message: String)
    case invalidSQLiteTree(message: String)
}

extension ExplainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            "Explain parsing is not implemented"
        case .malformedJSON:
            "The EXPLAIN payload is not valid JSON"
        case .invalidJSONStructure:
            "The JSON payload is not a PostgreSQL FORMAT JSON result"
        case .missingPlan:
            "The PostgreSQL EXPLAIN result does not contain a Plan object"
        case .missingNodeType:
            "The EXPLAIN plan node does not contain a Node Type"
        case .invalidNodeValue(let key):
            "The EXPLAIN plan field \(key) has an invalid value"
        case .invalidSQLiteText(let line, let message):
            "Invalid SQLite EXPLAIN text at line \(line): \(message)"
        case .invalidSQLiteRow(let index, let message):
            "Invalid SQLite EXPLAIN row \(index): \(message)"
        case .invalidSQLiteTree(let message):
            "Invalid SQLite EXPLAIN tree: \(message)"
        }
    }
}
