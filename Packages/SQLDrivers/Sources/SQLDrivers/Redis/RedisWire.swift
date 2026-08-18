import Foundation

public enum RedisError: Error, LocalizedError, Sendable, Equatable {
    case protocolError(String)
    case serverError(String)
    case notConnected
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .protocolError(let message): message
        case .serverError(let message): message
        case .notConnected: "Not connected"
        case .cancelled: "Cancelled"
        }
    }
}

public enum RedisReply: Sendable, Equatable {
    case status(String)
    case error(String)
    case integer(Int64)
    case bulk(Data?)
    case array([RedisReply]?)

    public var string: String? {
        switch self {
        case .status(let text): text
        case .error(let text): text
        case .integer(let value): String(value)
        case .bulk(let data): data.flatMap { String(data: $0, encoding: .utf8) }
        case .array: nil
        }
    }
}

public enum RedisCommand: Sendable {
    public static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var index = line.startIndex
        var quote: Character?

        while index < line.endIndex {
            let character = line[index]
            if let active = quote {
                if character == "\\" {
                    let next = line.index(after: index)
                    if next < line.endIndex {
                        current.append(line[next])
                        index = line.index(after: next)
                        continue
                    }
                }
                if character == active {
                    quote = nil
                    index = line.index(after: index)
                    continue
                }
                current.append(character)
                index = line.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                index = line.index(after: index)
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                index = line.index(after: index)
                continue
            }
            current.append(character)
            index = line.index(after: index)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    public static func splitStatements(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    public static func quote(_ argument: String) -> String {
        if argument.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ":._-")).contains($0) }) {
            return argument
        }
        let escaped = argument
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public static func line(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }

    public static func encode(_ arguments: [String]) -> Data {
        var data = Data("*\(arguments.count)\r\n".utf8)
        for argument in arguments {
            let bytes = Data(argument.utf8)
            data.append(Data("$\(bytes.count)\r\n".utf8))
            data.append(bytes)
            data.append(Data("\r\n".utf8))
        }
        return data
    }
}

struct RedisDecoder: Sendable {
    var data: Data
    var offset: Int = 0

    var remaining: Int { data.count - offset }

    mutating func append(_ chunk: Data) {
        data.append(chunk)
    }

    mutating func consumeReply() throws -> RedisReply? {
        let saved = offset
        do {
            let reply = try readReply()
            if offset > 0 {
                data.removeFirst(offset)
                offset = 0
            }
            return reply
        } catch RedisError.protocolError(let message) where message == "truncated" {
            offset = saved
            return nil
        }
    }

    mutating func readReply() throws -> RedisReply {
        guard offset < data.count else { throw RedisError.protocolError("truncated") }
        let type = data[data.startIndex + offset]
        offset += 1
        switch type {
        case UInt8(ascii: "+"):
            return .status(try readLine())
        case UInt8(ascii: "-"):
            return .error(try readLine())
        case UInt8(ascii: ":"):
            let line = try readLine()
            guard let value = Int64(line) else {
                throw RedisError.protocolError("Invalid Redis integer")
            }
            return .integer(value)
        case UInt8(ascii: "$"):
            let line = try readLine()
            guard let length = Int(line) else {
                throw RedisError.protocolError("Invalid Redis bulk length")
            }
            if length < 0 { return .bulk(nil) }
            let bytes = try readBytes(length)
            try expectCRLF()
            return .bulk(bytes)
        case UInt8(ascii: "*"):
            let line = try readLine()
            guard let count = Int(line) else {
                throw RedisError.protocolError("Invalid Redis array length")
            }
            if count < 0 { return .array(nil) }
            var items: [RedisReply] = []
            items.reserveCapacity(count)
            for _ in 0..<count {
                items.append(try readReply())
            }
            return .array(items)
        default:
            throw RedisError.protocolError("Unknown Redis reply type 0x\(String(type, radix: 16))")
        }
    }

    private mutating func readLine() throws -> String {
        var index = offset
        while index + 1 < data.count {
            if data[data.startIndex + index] == 13, data[data.startIndex + index + 1] == 10 {
                let slice = data[(data.startIndex + offset)..<(data.startIndex + index)]
                offset = index + 2
                return String(decoding: slice, as: UTF8.self)
            }
            index += 1
        }
        throw RedisError.protocolError("truncated")
    }

    private mutating func readBytes(_ count: Int) throws -> Data {
        guard remaining >= count else { throw RedisError.protocolError("truncated") }
        let slice = data[(data.startIndex + offset)..<(data.startIndex + offset + count)]
        offset += count
        return Data(slice)
    }

    private mutating func expectCRLF() throws {
        guard remaining >= 2,
              data[data.startIndex + offset] == 13,
              data[data.startIndex + offset + 1] == 10 else {
            throw RedisError.protocolError("truncated")
        }
        offset += 2
    }
}
