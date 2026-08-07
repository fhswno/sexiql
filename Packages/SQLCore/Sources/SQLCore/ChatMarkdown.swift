import Foundation

public enum ChatMarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case list(ordered: Bool, items: [String])
    case code(language: String?, code: String)
}

public enum ChatMarkdownParser: Sendable {
    public static func parse(_ text: String) -> [ChatMarkdownBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return [] }

        var blocks: [ChatMarkdownBlock] = []
        var i = normalized.startIndex
        var proseBuffer = ""

        func flushProse() {
            let chunks = splitProse(proseBuffer)
            blocks.append(contentsOf: chunks)
            proseBuffer = ""
        }

        while i < normalized.endIndex {
            if let fence = matchFenceOpen(normalized, from: i) {
                flushProse()
                i = fence.contentStart
                if let close = findFenceClose(normalized, from: i, marker: fence.marker) {
                    let body = String(normalized[i..<close.bodyEnd])
                    let code = stripFenceBody(body)
                    blocks.append(.code(language: fence.language, code: code))
                    i = close.afterClose
                } else {
                    let body = String(normalized[i...])
                    blocks.append(.code(language: fence.language, code: stripFenceBody(body)))
                    i = normalized.endIndex
                }
            } else {
                proseBuffer.append(normalized[i])
                i = normalized.index(after: i)
            }
        }
        flushProse()
        return mergeTrivial(blocks)
    }

    public static func isSQLInsertable(language: String?, code: String) -> Bool {
        if let language {
            let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !lang.isEmpty {
                let sqlLangs: Set<String> = [
                    "sql", "postgresql", "postgres", "pgsql", "mysql", "mariadb",
                    "sqlite", "tsql", "plsql", "psql",
                ]
                if sqlLangs.contains(lang) { return true }
            }
        }
        return looksLikeSQL(code)
    }

    // MARK: - Fence scanning

    private struct FenceOpen {
        var language: String?
        var contentStart: String.Index
        var marker: String
    }

    private struct FenceClose {
        var bodyEnd: String.Index
        var afterClose: String.Index
    }

    private static func matchFenceOpen(_ text: String, from start: String.Index) -> FenceOpen? {
        if start != text.startIndex {
            let prev = text.index(before: start)
            if text[prev] != "\n" { return nil }
        }

        var i = start
        var spaces = 0
        while i < text.endIndex, text[i] == " ", spaces < 3 {
            spaces += 1
            i = text.index(after: i)
        }
        guard i < text.endIndex, text[i] == "`" else { return nil }

        var ticks = 0
        var j = i
        while j < text.endIndex, text[j] == "`" {
            ticks += 1
            j = text.index(after: j)
        }
        guard ticks >= 3 else { return nil }

        let marker = String(repeating: "`", count: ticks)
        var langEnd = j
        while langEnd < text.endIndex, text[langEnd] != "\n" {
            langEnd = text.index(after: langEnd)
        }
        let langRaw = String(text[j..<langEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let language = langRaw.isEmpty ? nil : String(langRaw.split(whereSeparator: { $0.isWhitespace }).first ?? Substring())

        var contentStart = langEnd
        if contentStart < text.endIndex, text[contentStart] == "\n" {
            contentStart = text.index(after: contentStart)
        }
        return FenceOpen(language: language, contentStart: contentStart, marker: marker)
    }

    private static func findFenceClose(_ text: String, from start: String.Index, marker: String) -> FenceClose? {
        var i = start
        while i < text.endIndex {
            // Line start?
            let lineStart = i
            if lineStart != text.startIndex {
                let prev = text.index(before: lineStart)
                if text[prev] != "\n" {
                    i = text.index(after: i)
                    continue
                }
            }
            var j = lineStart
            var spaces = 0
            while j < text.endIndex, text[j] == " ", spaces < 3 {
                spaces += 1
                j = text.index(after: j)
            }
            if text[j...].hasPrefix(marker) {
                let k = text.index(j, offsetBy: marker.count)
                var onlyWS = true
                var endLine = k
                while endLine < text.endIndex, text[endLine] != "\n" {
                    if !text[endLine].isWhitespace { onlyWS = false; break }
                    endLine = text.index(after: endLine)
                }
                if onlyWS {
                    var after = endLine
                    if after < text.endIndex, text[after] == "\n" {
                        after = text.index(after: after)
                    }
                    var bodyEnd = lineStart
                    if bodyEnd > text.startIndex {
                        let before = text.index(before: bodyEnd)
                        if text[before] == "\n" {
                            bodyEnd = before
                        }
                    }
                    return FenceClose(bodyEnd: bodyEnd, afterClose: after)
                }
            }
            // Advance to next line.
            if let nl = text[i...].firstIndex(of: "\n") {
                i = text.index(after: nl)
            } else {
                break
            }
        }
        return nil
    }

    private static func stripFenceBody(_ body: String) -> String {
        var s = body
        if s.hasPrefix("\n") { s.removeFirst() }
        if s.hasSuffix("\n") { s.removeLast() }
        return s
    }

    // MARK: - Prose → paragraphs / lists

    private static func splitProse(_ raw: String) -> [ChatMarkdownBlock] {
        let text = raw.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return [] }

        let chunks = text.components(separatedBy: "\n\n")
        var out: [ChatMarkdownBlock] = []
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let list = parseList(trimmed) {
                out.append(list)
            } else {
                let collapsed = trimmed
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                out.append(.paragraph(collapsed))
            }
        }
        return out
    }

    private static func parseList(_ chunk: String) -> ChatMarkdownBlock? {
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }

        var unordered: [String] = []
        var ordered: [String] = []
        var mode: Bool?

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            if let item = matchUnordered(t) {
                if mode == true { return nil }
                mode = false
                unordered.append(item)
            } else if let item = matchOrdered(t) {
                if mode == false { return nil }
                mode = true
                ordered.append(item)
            } else {
                return nil
            }
        }
        guard let mode else { return nil }
        if mode {
            guard ordered.count >= 1 else { return nil }
            return .list(ordered: true, items: ordered)
        } else {
            guard unordered.count >= 1 else { return nil }
            return .list(ordered: false, items: unordered)
        }
    }

    private static func matchUnordered(_ line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let c = line[line.startIndex]
        guard c == "-" || c == "*" || c == "+" else { return nil }
        let second = line[line.index(after: line.startIndex)]
        guard second == " " || second == "\t" else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func matchOrdered(_ line: String) -> String? {
        var i = line.startIndex
        var digits = 0
        while i < line.endIndex, line[i].isNumber, digits < 4 {
            digits += 1
            i = line.index(after: i)
        }
        guard digits > 0, i < line.endIndex, line[i] == "." else { return nil }
        i = line.index(after: i)
        guard i < line.endIndex, line[i] == " " || line[i] == "\t" else { return nil }
        i = line.index(after: i)
        return String(line[i...]).trimmingCharacters(in: .whitespaces)
    }

    private static func mergeTrivial(_ blocks: [ChatMarkdownBlock]) -> [ChatMarkdownBlock] {
        blocks.filter { block in
            switch block {
            case .paragraph(let t):
                return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .list(_, let items):
                return !items.isEmpty
            case .code:
                return true
            }
        }
    }

    private static func looksLikeSQL(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return false }
        let head = trimmed.prefix(64).lowercased()
        let keywords = [
            "select ", "insert ", "update ", "delete ", "with ", "create ",
            "alter ", "drop ", "explain ", "begin", "commit", "pragma ",
            "replace ", "truncate ", "grant ", "revoke ", "call ", "merge ",
        ]
        return keywords.contains { head.hasPrefix($0) || head.hasPrefix($0.trimmingCharacters(in: .whitespaces)) }
    }
}
