import Foundation

public struct NarrationSegment: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case overview
        case cluster
        case path
        case detail
        case closing
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var text: String
    public var tableIDs: [String]
    public var edgeIDs: [String]

    public init(
        id: String,
        kind: Kind,
        title: String,
        text: String,
        tableIDs: [String] = [],
        edgeIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.tableIDs = tableIDs
        self.edgeIDs = edgeIDs
    }
}

public struct CanvasNarrationParser {
    private let knownTableIDs: Set<String>
    private let knownEdgeIDs: Set<String>
    private var buffer = ""
    private var jsonAccumulator = ""
    private var nextIndex = 1
    private var lastText: String?
    private let maxSegments = 8

    public init(knownTableIDs: Set<String>, knownEdgeIDs: Set<String>) {
        self.knownTableIDs = knownTableIDs
        self.knownEdgeIDs = knownEdgeIDs
    }

    public mutating func ingest(_ chunk: String) -> [NarrationSegment] {
        buffer += chunk
        var segments: [NarrationSegment] = []

        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .whitespaces)
            buffer = String(buffer[buffer.index(after: newline)...])
            if line.isEmpty { continue }
            if line.hasPrefix("```") { continue }
            if segments.count >= maxSegments { continue }
            if let segment = parse(line: line) {
                if segment.text == lastText { continue }
                lastText = segment.text
                segments.append(segment)
            }
        }
        return segments
    }

    public mutating func finish() -> [NarrationSegment] {
        var segments: [NarrationSegment] = []
        let remainder = buffer.trimmingCharacters(in: .whitespaces)
        buffer = ""

        if !jsonAccumulator.isEmpty {
            let candidate = remainder.isEmpty ? jsonAccumulator : jsonAccumulator + "\n" + remainder
            if let dto = decode(candidate) {
                if segments.count < maxSegments, dto.text ?? "" != lastText {
                    segments.append(segment(from: dto))
                    lastText = dto.text
                }
            } else {
                for line in candidate.split(separator: "\n") {
                    if line.hasPrefix("```") { continue }
                    if segments.count >= maxSegments { break }
                    let text = String(line).trimmingCharacters(in: .whitespaces)
                    if text.isEmpty || text == lastText { continue }
                    segments.append(proseSegment(text))
                    lastText = text
                }
            }
            jsonAccumulator = ""
            return segments
        }

        guard !remainder.isEmpty else { return segments }
        if remainder.hasPrefix("```") { return segments }
        if segments.count >= maxSegments { return segments }
        if remainder == lastText { return segments }
        if let dto = decode(remainder) {
            segments.append(segment(from: dto))
            lastText = dto.text
            return segments
        }
        segments.append(proseSegment(remainder))
        lastText = remainder
        return segments
    }

    // MARK: - Line Parsing

    private mutating func parse(line: String) -> NarrationSegment? {
        let startsStructured = line.hasPrefix("{") || line.hasPrefix("[")
        guard startsStructured || !jsonAccumulator.isEmpty else {
            return proseSegment(line)
        }
        let candidate = jsonAccumulator.isEmpty ? line : jsonAccumulator + "\n" + line
        if let dto = decode(candidate) {
            jsonAccumulator = ""
            return segment(from: dto)
        }
        if candidate.count > 4_000 {
            jsonAccumulator = ""
            return proseSegment(line)
        }
        jsonAccumulator = candidate
        return nil
    }

    private mutating func proseSegment(_ text: String) -> NarrationSegment {
        let id = "seg-\(nextIndex)"
        nextIndex += 1
        return NarrationSegment(id: id, kind: .detail, title: "", text: text)
    }

    private struct SegmentDTO: Decodable {
        var kind: String?
        var title: String?
        var text: String?
        var tables: [String]?
        var edges: [String]?
    }

    private func decode(_ json: String) -> SegmentDTO? {
        let decoder = JSONDecoder()
        if let dto = try? decoder.decode(SegmentDTO.self, from: Data(json.utf8)) {
            return dto
        }
        if let array = try? decoder.decode([SegmentDTO].self, from: Data(json.utf8)), let first = array.first {
            return first
        }
        return nil
    }

    private mutating func segment(from dto: SegmentDTO) -> NarrationSegment {
        segment(id: nil, kind: dto.kind, title: dto.title, text: dto.text, tables: dto.tables, edges: dto.edges)
    }

    private mutating func segment(
        id: String?,
        kind rawKind: String?,
        title: String?,
        text: String?,
        tables: [String]?,
        edges: [String]?
    ) -> NarrationSegment {
        let kind = NarrationSegment.Kind(rawValue: rawKind ?? "") ?? .detail
        let validTables = (tables ?? []).filter { knownTableIDs.contains($0) }
        let validEdges = (edges ?? []).filter { knownEdgeIDs.contains($0) }
        let identifier = id ?? "seg-\(nextIndex)"
        nextIndex += 1
        return NarrationSegment(
            id: identifier,
            kind: kind,
            title: title ?? "",
            text: text ?? "",
            tableIDs: validTables,
            edgeIDs: validEdges
        )
    }
}
