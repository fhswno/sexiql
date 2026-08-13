import Foundation

public enum SQLCompletionKind: Sendable, Equatable {
    case keyword
    case table
    case view
    case column
}

public struct SQLCompletionItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: SQLCompletionKind
    public var label: String
    public var insertText: String
    public var detail: String?

    public init(
        kind: SQLCompletionKind,
        label: String,
        insertText: String,
        detail: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.insertText = insertText
        self.detail = detail
        self.id = "\(kind)-\(label)-\(detail ?? "")"
    }
}

public struct SQLCompletionColumn: Sendable, Equatable {
    public var name: String
    public var insertText: String
    public var detail: String?
    public var tableName: String

    public init(name: String, insertText: String, detail: String? = nil, tableName: String) {
        self.name = name
        self.insertText = insertText
        self.detail = detail
        self.tableName = tableName
    }
}

public struct SQLCompletionObject: Sendable, Equatable {
    public var name: String
    public var schema: String?
    public var insertText: String
    public var kind: SQLCompletionKind
    public var columns: [SQLCompletionColumn]

    public init(
        name: String,
        insertText: String,
        kind: SQLCompletionKind,
        columns: [SQLCompletionColumn] = [],
        schema: String? = nil
    ) {
        self.name = name
        self.schema = schema
        self.insertText = insertText
        self.kind = kind
        self.columns = columns
    }

    public var qualifiedName: String {
        if let schema, !schema.isEmpty { return "\(schema).\(name)" }
        return name
    }
}

public struct SQLCompletionCatalog: Sendable, Equatable {
    public var keywords: [String]
    public var objects: [SQLCompletionObject]

    public init(keywords: [String] = Array(SQLLexer.keywords).sorted(), objects: [SQLCompletionObject] = []) {
        self.keywords = keywords
        self.objects = objects
    }

    public static let keywordsOnly = SQLCompletionCatalog()
}

public struct SQLCompletionResult: Sendable, Equatable {
    public var items: [SQLCompletionItem]
    public var replaceRange: NSRange
    public var pendingQualifier: String?

    public init(items: [SQLCompletionItem], replaceRange: NSRange, pendingQualifier: String? = nil) {
        self.items = items
        self.replaceRange = replaceRange
        self.pendingQualifier = pendingQualifier
    }

    public static let empty = SQLCompletionResult(items: [], replaceRange: NSRange(location: 0, length: 0))
}

public enum SQLCompletionContext: Sendable, Equatable {
    case general
    case relation
    case column(qualifier: String?)
    case columnValue
}

public struct SQLCompletionEngine: Sendable {
    public var limit: Int

    public init(limit: Int = 40) {
        self.limit = limit
    }

    public func suggestions(
        sql: String,
        cursor: Int,
        catalog: SQLCompletionCatalog,
        force: Bool
    ) -> SQLCompletionResult {
        let units = Array(sql.utf16)
        let cursor = min(max(cursor, 0), units.count)
        let tokens = SQLLexer().tokenize(sql)

        if isInsideStringOrComment(cursor: cursor, tokens: tokens) {
            return .empty
        }

        let query = parseQuery(tokens: tokens, cursor: cursor, units: units)
        if !force, query.qualifier == nil, query.prefix.utf16.count < 2 {
            return .empty
        }

        let items = rankedItems(query: query, catalog: catalog, force: force)
        var pending: String?
        if case .column(let qualifier) = query.context, let qualifier, !qualifier.isEmpty {
            let resolved = query.aliases[qualifier.lowercased()] ?? qualifier
            let hasCols = catalog.objects.contains {
                $0.name.caseInsensitiveCompare(resolved) == .orderedSame && !$0.columns.isEmpty
            }
            if !hasCols { pending = resolved }
        }
        return SQLCompletionResult(items: items, replaceRange: query.replaceRange, pendingQualifier: pending)
    }

    public static func objectsDeclared(in sql: String) -> [SQLCompletionObject] {
        let tokens = SQLLexer().tokenize(sql)
        var objects: [SQLCompletionObject] = []
        var i = 0
        while i < tokens.count {
            defer { i += 1 }
            guard tokens[i].kind == .keyword, tokens[i].text.uppercased() == "CREATE" else { continue }
            var j = i + 1
            while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
            guard j < tokens.count, tokens[j].kind == .keyword, tokens[j].text.uppercased() == "TABLE" else { continue }
            j += 1
            while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
            if j + 2 < tokens.count,
               tokens[j].kind == .keyword, tokens[j].text.uppercased() == "IF",
               tokens[j + 2].kind == .keyword, tokens[j + 2].text.uppercased() == "EXISTS" {
                j += 3
                while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
            }
            guard j < tokens.count, tokens[j].kind == .identifier || tokens[j].kind == .keyword else { continue }
            var table = tokens[j].text
            j += 1
            while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
            if j < tokens.count, tokens[j].text == ".", j + 1 < tokens.count {
                var n = j + 1
                while n < tokens.count, tokens[n].kind == .whitespace { n += 1 }
                if n < tokens.count, tokens[n].kind == .identifier || tokens[n].kind == .keyword {
                    table = tokens[n].text
                    j = n + 1
                }
            }
            while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
            guard j < tokens.count, tokens[j].text == "(" else { continue }
            j += 1
            var columns: [SQLCompletionColumn] = []
            var expectName = true
            while j < tokens.count {
                let token = tokens[j]
                if token.text == ")" { break }
                if token.kind == .whitespace {
                    j += 1
                    continue
                }
                if token.text == "," {
                    expectName = true
                    j += 1
                    continue
                }
                if expectName, token.kind == .identifier || token.kind == .keyword {
                    let word = token.text.uppercased()
                    if ["CONSTRAINT", "PRIMARY", "UNIQUE", "FOREIGN", "CHECK", "EXCLUDE"].contains(word) {
                        expectName = false
                    } else {
                        columns.append(
                            SQLCompletionColumn(name: token.text, insertText: token.text, tableName: table)
                        )
                        expectName = false
                    }
                }
                j += 1
            }
            objects.append(
                SQLCompletionObject(name: table, insertText: table, kind: .table, columns: columns)
            )
        }
        return objects
    }

    public static func needsQuoting(_ name: String) -> Bool {
        if SQLLexer.keywords.contains(name.uppercased()) { return true }
        guard let first = name.unicodeScalars.first else { return true }
        if !(first == "_" || CharacterSet.letters.contains(first)) { return true }
        return name.unicodeScalars.contains { scalar in
            !(scalar == "_" || CharacterSet.alphanumerics.contains(scalar))
        }
    }

    // MARK: - Parse

    private struct Query {
        var prefix: String
        var qualifier: String?
        var context: SQLCompletionContext
        var replaceRange: NSRange
        var aliases: [String: String]
    }

    private func parseQuery(tokens: [SQLToken], cursor: Int, units: [UInt16]) -> Query {
        let aliases = aliasMap(tokens)
        let prefixInfo = prefixAtCursor(tokens: tokens, cursor: cursor, units: units)
        let insertTable = prefixInfo.qualifier == nil
            ? insertColumnListTable(tokens: tokens, before: prefixInfo.replaceRange.location)
            : nil
        let inRelation = isRelationContext(tokens: tokens, before: prefixInfo.replaceRange.location)
        let context: SQLCompletionContext
        let qualifier: String?
        if let insertTable {
            context = .column(qualifier: insertTable)
            qualifier = insertTable
        } else if let q = prefixInfo.qualifier, !inRelation {
            context = .column(qualifier: q)
            qualifier = q
        } else if inRelation {
            context = .relation
            qualifier = prefixInfo.qualifier
        } else if isColumnValueContext(tokens: tokens, before: prefixInfo.replaceRange.location) {
            context = .columnValue
            qualifier = prefixInfo.qualifier
        } else {
            context = .general
            qualifier = prefixInfo.qualifier
        }
        return Query(
            prefix: prefixInfo.prefix,
            qualifier: qualifier,
            context: context,
            replaceRange: prefixInfo.replaceRange,
            aliases: aliases
        )
    }

    private func prefixAtCursor(
        tokens: [SQLToken],
        cursor: Int,
        units: [UInt16]
    ) -> (prefix: String, qualifier: String?, replaceRange: NSRange) {
        if cursor > 0, units[cursor - 1] == 0x2E {
            let qualifier = identifierBeforeDot(tokens: tokens, dotEnd: cursor)
            return ("", qualifier, NSRange(location: cursor, length: 0))
        }

        var i = tokens.count - 1
        while i >= 0, tokens[i].location >= cursor {
            i -= 1
        }
        guard i >= 0 else {
            return ("", nil, NSRange(location: cursor, length: 0))
        }

        let token = tokens[i]
        let tokenEnd = token.location + token.length
        let touching = tokenEnd >= cursor && token.location < cursor

        if touching, token.kind == .identifier || token.kind == .keyword {
            let prefix = String(decoding: units[token.location..<cursor], as: UTF16.self)
            var qualifier: String?
            var j = i - 1
            while j >= 0, tokens[j].kind == .whitespace { j -= 1 }
            if j >= 0, tokens[j].text == "." {
                var k = j - 1
                while k >= 0, tokens[k].kind == .whitespace { k -= 1 }
                if k >= 0, tokens[k].kind == .identifier || tokens[k].kind == .keyword {
                    qualifier = tokens[k].text
                }
            }
            return (prefix, qualifier, NSRange(location: token.location, length: cursor - token.location))
        }

        if touching, token.text == "." {
            var k = i - 1
            while k >= 0, tokens[k].kind == .whitespace { k -= 1 }
            let qualifier = (k >= 0 && (tokens[k].kind == .identifier || tokens[k].kind == .keyword))
                ? tokens[k].text : ""
            return ("", qualifier, NSRange(location: cursor, length: 0))
        }

        var j = i
        while j >= 0, tokens[j].kind == .whitespace { j -= 1 }
        if j >= 0, tokens[j].text == "." {
            var k = j - 1
            while k >= 0, tokens[k].kind == .whitespace { k -= 1 }
            let qualifier = (k >= 0 && (tokens[k].kind == .identifier || tokens[k].kind == .keyword))
                ? tokens[k].text : ""
            return ("", qualifier, NSRange(location: cursor, length: 0))
        }

        return ("", nil, NSRange(location: cursor, length: 0))
    }

    private func identifierBeforeDot(tokens: [SQLToken], dotEnd: Int) -> String? {
        let dotStart = dotEnd - 1
        var i = tokens.count - 1
        while i >= 0, tokens[i].location >= dotStart { i -= 1 }
        while i >= 0, tokens[i].kind == .whitespace { i -= 1 }
        guard i >= 0, tokens[i].kind == .identifier || tokens[i].kind == .keyword else { return "" }
        return tokens[i].text
    }

    private func isInsideStringOrComment(cursor: Int, tokens: [SQLToken]) -> Bool {
        for token in tokens {
            let start = token.location
            let end = token.location + token.length
            if cursor > start, cursor < end, token.kind == .string || token.kind == .comment {
                return true
            }
        }
        return false
    }

    private func insertColumnListTable(tokens: [SQLToken], before location: Int) -> String? {
        var i = tokens.count - 1
        while i >= 0, tokens[i].location >= location { i -= 1 }
        while i >= 0, tokens[i].kind == .whitespace { i -= 1 }
        while i >= 0, tokens[i].text == "," || tokens[i].kind == .identifier || tokens[i].kind == .keyword {
            if tokens[i].text == "(" { break }
            i -= 1
            while i >= 0, tokens[i].kind == .whitespace { i -= 1 }
        }
        guard i >= 0, tokens[i].text == "(" else { return nil }
        i -= 1
        while i >= 0, tokens[i].kind == .whitespace { i -= 1 }
        guard i >= 0, tokens[i].kind == .identifier || tokens[i].kind == .keyword else { return nil }
        let table = tokens[i].text
        i -= 1
        while i >= 0, tokens[i].kind == .whitespace { i -= 1 }
        if i >= 0, tokens[i].text == "." {
            i -= 1
            while i >= 0, tokens[i].kind == .whitespace { i -= 1 }
        }
        while i >= 0, tokens[i].kind == .whitespace { i -= 1 }
        guard i >= 0, tokens[i].kind == .keyword, tokens[i].text.uppercased() == "INTO" else { return nil }
        return table
    }

    private func isColumnValueContext(tokens: [SQLToken], before location: Int) -> Bool {
        var i = tokens.count - 1
        while i >= 0, tokens[i].location >= location { i -= 1 }
        while i >= 0 {
            let token = tokens[i]
            if token.kind == .whitespace {
                i -= 1
                continue
            }
            if token.kind == .keyword {
                let word = token.text.uppercased()
                if ["WHERE", "HAVING", "ON", "AND", "OR", "SET", "WHEN", "RETURNING"].contains(word) {
                    return true
                }
                if word == "BY" { return true }
                if word == "SELECT" { return true }
                if ["FROM", "JOIN", "INTO", "UPDATE", "TABLE"].contains(word) { return false }
            }
            i -= 1
        }
        return false
    }

    private func isRelationContext(tokens: [SQLToken], before location: Int) -> Bool {
        var i = tokens.count - 1
        while i >= 0, tokens[i].location >= location {
            i -= 1
        }
        while i >= 0 {
            let token = tokens[i]
            if token.kind == .whitespace {
                i -= 1
                continue
            }
            if token.kind == .keyword {
                let word = token.text.uppercased()
                if ["FROM", "JOIN", "INTO", "UPDATE", "TABLE"].contains(word) { return true }
                if ["ON", "WHERE", "SET", "RETURNING", "SELECT", "BY", "HAVING", "AND", "OR"].contains(word) {
                    return false
                }
            }
            if token.text == "," { return true }
            if token.text == "." { i -= 1; continue }
            i -= 1
            if token.kind == .identifier { continue }
            return false
        }
        return false
    }

    private func aliasMap(_ tokens: [SQLToken]) -> [String: String] {
        var map: [String: String] = [:]
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token.kind == .keyword {
                let word = token.text.uppercased()
                if ["FROM", "JOIN", "INTO", "UPDATE"].contains(word) {
                    var j = i + 1
                    while j < tokens.count, tokens[j].kind == .whitespace { j += 1 }
                    guard j < tokens.count, tokens[j].kind == .identifier || tokens[j].kind == .keyword else {
                        i += 1
                        continue
                    }
                    var table = tokens[j].text
                    var k = j + 1
                    while k + 1 < tokens.count {
                        if tokens[k].kind == .whitespace {
                            k += 1
                            continue
                        }
                        if tokens[k].text == ".", k + 1 < tokens.count {
                            var n = k + 1
                            while n < tokens.count, tokens[n].kind == .whitespace { n += 1 }
                            if n < tokens.count, tokens[n].kind == .identifier || tokens[n].kind == .keyword {
                                table = tokens[n].text
                                k = n + 1
                                continue
                            }
                        }
                        break
                    }
                    while k < tokens.count, tokens[k].kind == .whitespace { k += 1 }
                    if k < tokens.count, tokens[k].kind == .keyword, tokens[k].text.uppercased() == "AS" {
                        k += 1
                        while k < tokens.count, tokens[k].kind == .whitespace { k += 1 }
                    }
                    if k < tokens.count, tokens[k].kind == .identifier {
                        let alias = tokens[k].text
                        if !isClauseKeyword(alias) {
                            map[alias.lowercased()] = table
                        }
                    }
                    map[table.lowercased()] = table
                }
            }
            i += 1
        }
        return map
    }

    private func isClauseKeyword(_ text: String) -> Bool {
        ["ON", "WHERE", "SET", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS",
         "ORDER", "GROUP", "LIMIT", "OFFSET", "RETURNING", "AND", "OR", "HAVING"].contains(text.uppercased())
    }

    // MARK: - Rank

    private func rankedItems(query: Query, catalog: SQLCompletionCatalog, force: Bool) -> [SQLCompletionItem] {
        let needle = query.prefix
        var scored: [(SQLCompletionItem, Int)] = []

        switch query.context {
        case .column(let qualifier):
            let resolved = resolveQualifier(qualifier, aliases: query.aliases, catalog: catalog)
            let columns: [SQLCompletionColumn]
            if let resolved {
                columns = catalog.objects
                    .filter { $0.name.caseInsensitiveCompare(resolved) == .orderedSame }
                    .flatMap(\.columns)
            } else if qualifier == nil || qualifier?.isEmpty == true {
                columns = catalog.objects.flatMap(\.columns)
            } else {
                columns = catalog.objects
                    .filter { $0.name.localizedCaseInsensitiveContains(qualifier ?? "") }
                    .flatMap(\.columns)
            }
            for column in columns {
                if let rank = matchRank(label: column.name, prefix: needle, force: force || query.qualifier != nil) {
                    scored.append((
                        SQLCompletionItem(
                            kind: .column,
                            label: column.name,
                            insertText: column.insertText,
                            detail: column.detail
                        ),
                        rank
                    ))
                }
            }
        case .columnValue:
            let referenced = Set(query.aliases.values.map { $0.lowercased() })
            let columnSource = catalog.objects.filter { object in
                referenced.isEmpty || referenced.contains(object.name.lowercased())
            }
            for column in columnSource.flatMap(\.columns) {
                if let rank = matchRank(label: column.name, prefix: needle, force: force) {
                    scored.append((
                        SQLCompletionItem(
                            kind: .column,
                            label: column.name,
                            insertText: column.insertText,
                            detail: column.detail
                        ),
                        rank
                    ))
                }
            }
            for word in catalog.keywords {
                if let rank = matchRank(label: word, prefix: needle, force: force) {
                    scored.append((
                        SQLCompletionItem(kind: .keyword, label: word, insertText: word),
                        rank + 10
                    ))
                }
            }
        case .relation:
            let schemaFilter = query.qualifier
            let knownSchema = schemaFilter.map { qualifier in
                catalog.objects.contains {
                    ($0.schema ?? "").caseInsensitiveCompare(qualifier) == .orderedSame
                }
            } ?? false
            if let schemaFilter, knownSchema {
                for object in catalog.objects {
                    guard let schema = object.schema,
                          schema.caseInsensitiveCompare(schemaFilter) == .orderedSame else { continue }
                    if let rank = matchRank(
                        label: object.name,
                        prefix: needle,
                        force: force || true
                    ) {
                        scored.append((
                            SQLCompletionItem(
                                kind: object.kind,
                                label: object.qualifiedName,
                                insertText: object.name
                            ),
                            rank
                        ))
                    }
                }
            } else {
                for object in catalog.objects {
                    let rank = matchRank(label: object.name, prefix: needle, force: force)
                        ?? matchRank(label: object.qualifiedName, prefix: needle, force: force)
                    guard let rank else { continue }
                    scored.append((
                        SQLCompletionItem(
                            kind: object.kind,
                            label: object.qualifiedName,
                            insertText: object.insertText
                        ),
                        rank
                    ))
                }
            }
            for word in catalog.keywords {
                if let rank = matchRank(label: word, prefix: needle, force: force) {
                    scored.append((
                        SQLCompletionItem(kind: .keyword, label: word, insertText: word),
                        rank + 8
                    ))
                }
            }
        case .general:
            for word in catalog.keywords {
                if let rank = matchRank(label: word, prefix: needle, force: force) {
                    let lead = needle.isEmpty && Self.leadKeywords.contains(word) ? 0 : rank
                    scored.append((
                        SQLCompletionItem(kind: .keyword, label: word, insertText: word),
                        lead
                    ))
                }
            }
            for object in catalog.objects {
                if let rank = matchRank(label: object.name, prefix: needle, force: force) {
                    scored.append((
                        SQLCompletionItem(kind: object.kind, label: object.name, insertText: object.insertText),
                        rank + 1
                    ))
                }
            }
        }

        scored.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.label.localizedCaseInsensitiveCompare(rhs.0.label) == .orderedAscending
        }

        var seen: Set<String> = []
        var items: [SQLCompletionItem] = []
        for (item, _) in scored {
            if seen.insert(item.id).inserted {
                items.append(item)
            }
            if items.count >= limit { break }
        }
        return items
    }

    private func resolveQualifier(
        _ qualifier: String?,
        aliases: [String: String],
        catalog: SQLCompletionCatalog
    ) -> String? {
        guard let qualifier, !qualifier.isEmpty else { return nil }
        if let mapped = aliases[qualifier.lowercased()] { return mapped }
        if catalog.objects.contains(where: { $0.name.caseInsensitiveCompare(qualifier) == .orderedSame }) {
            return qualifier
        }
        return nil
    }

    private static let leadKeywords: Set<String> = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
        "WITH", "EXPLAIN", "BEGIN", "COMMIT", "ROLLBACK",
    ]

    private func matchRank(label: String, prefix: String, force: Bool) -> Int? {
        if prefix.isEmpty { return force ? 5 : nil }
        if label.lowercased().hasPrefix(prefix.lowercased()) { return 0 }
        if label.localizedCaseInsensitiveContains(prefix) { return 4 }
        return nil
    }
}
