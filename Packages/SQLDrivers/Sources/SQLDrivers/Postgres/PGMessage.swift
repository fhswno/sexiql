import Foundation

public struct PGMessageType: RawRepresentable, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let authentication = PGMessageType(rawValue: 0x52)      // 'R'
    public static let backendKeyData = PGMessageType(rawValue: 0x4B)      // 'K'
    public static let parameterStatus = PGMessageType(rawValue: 0x53)     // 'S'
    public static let rowDescription = PGMessageType(rawValue: 0x54)      // 'T'
    public static let dataRow = PGMessageType(rawValue: 0x44)             // 'D'
    public static let commandComplete = PGMessageType(rawValue: 0x43)     // 'C'
    public static let readyForQuery = PGMessageType(rawValue: 0x5A)       // 'Z'
    public static let errorResponse = PGMessageType(rawValue: 0x45)       // 'E'
    public static let noticeResponse = PGMessageType(rawValue: 0x4E)      // 'N'
    public static let emptyQueryResponse = PGMessageType(rawValue: 0x49)  // 'I'
    public static let notificationResponse = PGMessageType(rawValue: 0x41) // 'A'
    public static let passwordMessage = PGMessageType(rawValue: 0x70)     // 'p'
    public static let query = PGMessageType(rawValue: 0x51)               // 'Q'
    public static let terminate = PGMessageType(rawValue: 0x58)           // 'X'

    // Extended query protocol (sent by client):
    public static let parse = PGMessageType(rawValue: 0x50)               // 'P'
    public static let bind = PGMessageType(rawValue: 0x42)                // 'B'
    public static let describe = PGMessageType(rawValue: 0x44)            // 'D'
    public static let execute = PGMessageType(rawValue: 0x45)             // 'E'
    public static let sync = PGMessageType(rawValue: 0x53)                // 'S'

    // Extended query protocol (received by client):
    public static let parseComplete = PGMessageType(rawValue: 0x31)       // '1'
    public static let bindComplete = PGMessageType(rawValue: 0x32)        // '2'
    public static let closeComplete = PGMessageType(rawValue: 0x33)       // '3'
    public static let parameterDescription = PGMessageType(rawValue: 0x74) // 't'
    public static let noData = PGMessageType(rawValue: 0x6E)              // 'n'
    public static let portalSuspended = PGMessageType(rawValue: 0x73)     // 's'
}

public enum PGWireError: Error, LocalizedError, Sendable, Equatable {
    case truncated
    case invalidMessage
    case unsupportedAuth
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .truncated: "Truncated Postgres message"
        case .invalidMessage: "Invalid Postgres message"
        case .unsupportedAuth: "Unsupported Postgres authentication method"
        case .invalidUTF8: "Invalid UTF-8 in Postgres message"
        }
    }
}

public enum PGWire {
    public static func frame(_ type: UInt8, _ payload: Data) -> Data {
        var data = Data()
        data.append(type)
        data.append(int32(Int32(payload.count + 4)))
        data.append(payload)
        return data
    }

    public static func frameUntagged(_ payload: Data) -> Data {
        var data = Data()
        data.append(int32(Int32(payload.count + 4)))
        data.append(payload)
        return data
    }

    public static func cancelRequest(processID: Int32, secretKey: Int32) -> Data {
        var payload = Data()
        payload.append(int32(80877102))
        payload.append(int32(processID))
        payload.append(int32(secretKey))
        return frameUntagged(payload)
    }

    public static func int16(_ value: Int16) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    public static func int32(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    public static func cstring(_ string: String) -> Data {
        var data = Data(string.utf8)
        data.append(0)
        return data
    }

    public static func saslResponse(_ string: String) -> Data {
        var data = Data()
        data.append(cstring(string))
        data.append(0)
        return data
    }
}

public struct PGByteReader: Sendable {
    public let data: Data
    public private(set) var offset: Int = 0

    public init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public var isAtEnd: Bool { offset >= data.count }

    public mutating func readInt8() throws -> UInt8 {
        guard offset < data.count else { throw PGWireError.truncated }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    public mutating func readInt16() throws -> Int16 {
        let bytes = try readBytes(2)
        return Int16(bigEndian: bytes.withUnsafeBytes { $0.load(as: Int16.self) })
    }

    public mutating func readInt32() throws -> Int32 {
        let bytes = try readBytes(4)
        return Int32(bigEndian: bytes.withUnsafeBytes { $0.load(as: Int32.self) })
    }

    public mutating func readCString() throws -> String {
        let start = offset
        while offset < data.count && data[data.startIndex + offset] != 0 {
            offset += 1
        }
        guard offset < data.count else { throw PGWireError.truncated }
        let bytes = data[data.startIndex + start..<data.startIndex + offset]
        offset += 1
        guard let string = String(data: Data(bytes), encoding: .utf8) else {
            throw PGWireError.invalidUTF8
        }
        return string
    }

    public mutating func readBytes(_ count: Int) throws -> Data {
        guard offset + count <= data.count else { throw PGWireError.truncated }
        let bytes = data[data.startIndex + offset..<data.startIndex + offset + count]
        offset += count
        return Data(bytes)
    }

    public mutating func readString(_ count: Int) throws -> String {
        let bytes = try readBytes(count)
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw PGWireError.invalidUTF8
        }
        return string
    }
}
