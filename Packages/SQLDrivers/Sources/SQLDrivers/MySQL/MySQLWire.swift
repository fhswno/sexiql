import Foundation

public enum MySQLWireError: Error, LocalizedError, Sendable, Equatable {
    case truncated
    case invalidPacket
    case invalidHandshake
    case authenticationFailed(String)
    case unsupportedAuthentication(String)
    case serverError(code: Int, message: String, state: String?)
    case tlsRequired
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .truncated: "Truncated MySQL packet"
        case .invalidPacket: "Invalid MySQL packet"
        case .invalidHandshake: "Invalid MySQL handshake"
        case .authenticationFailed(let message): message
        case .unsupportedAuthentication(let plugin): "Unsupported MySQL auth plugin: \(plugin)"
        case .serverError(let code, let message, let state):
            if let state { "\(message) [\(code)/\(state)]" } else { "\(message) [\(code)]" }
        case .tlsRequired: "MySQL server requires TLS"
        case .protocolError(let message): message
        }
    }

    public var isQueryInterrupted: Bool {
        switch self {
        case .serverError(let code, let message, let state):
            if code == MySQLCancel.queryInterruptedCode || state == "70100" { return true }
            let text = message.lowercased()
            return text.contains("interrupted")
        default:
            return false
        }
    }
}

public enum MySQLCancel: Sendable {
    public static let queryInterruptedCode = 1317
    public static let noSuchThreadCode = 1094

    public static func killQuerySQL(connectionID: UInt32) -> String {
        "KILL QUERY \(connectionID)"
    }

    public static func isBenignKillError(_ error: MySQLWireError) -> Bool {
        if case .serverError(let code, _, _) = error, code == noSuchThreadCode {
            return true
        }
        return false
    }
}

public struct MySQLPacket: Sendable, Equatable {
    public var sequence: UInt8
    public var payload: Data

    public init(sequence: UInt8, payload: Data) {
        self.sequence = sequence
        self.payload = payload
    }

    public func encoded() -> Data {
        var data = Data()
        let length = payload.count
        data.append(UInt8(length & 0xff))
        data.append(UInt8((length >> 8) & 0xff))
        data.append(UInt8((length >> 16) & 0xff))
        data.append(sequence)
        data.append(payload)
        return data
    }
}

public struct MySQLByteReader: Sendable {
    public let data: Data
    public private(set) var offset: Int = 0

    public init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public var isAtEnd: Bool { offset >= data.count }

    public mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw MySQLWireError.truncated }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    public mutating func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(2)
        return UInt16(bytes[bytes.startIndex]) | (UInt16(bytes[bytes.startIndex + 1]) << 8)
    }

    public mutating func readUInt24() throws -> UInt32 {
        let bytes = try readBytes(3)
        return UInt32(bytes[bytes.startIndex])
            | (UInt32(bytes[bytes.startIndex + 1]) << 8)
            | (UInt32(bytes[bytes.startIndex + 2]) << 16)
    }

    public mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        return UInt32(bytes[bytes.startIndex])
            | (UInt32(bytes[bytes.startIndex + 1]) << 8)
            | (UInt32(bytes[bytes.startIndex + 2]) << 16)
            | (UInt32(bytes[bytes.startIndex + 3]) << 24)
    }

    public mutating func readUInt64() throws -> UInt64 {
        let bytes = try readBytes(8)
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[bytes.startIndex + index]) << UInt64(index * 8)
        }
        return value
    }

    public mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw MySQLWireError.truncated }
        let result = Data(data[data.startIndex + offset..<data.startIndex + offset + count])
        offset += count
        return result
    }

    public mutating func readString(_ count: Int) throws -> String {
        let bytes = try readBytes(count)
        return String(data: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
    }

    public mutating func readCString() throws -> String {
        let start = offset
        while offset < data.count && data[data.startIndex + offset] != 0 {
            offset += 1
        }
        guard offset < data.count else { throw MySQLWireError.truncated }
        let result = String(decoding: data[data.startIndex + start..<data.startIndex + offset], as: UTF8.self)
        offset += 1
        return result
    }

    /// Reads MySQL's length-encoded integer. `nil` means the NULL marker.
    public mutating func readLengthEncodedInteger() throws -> UInt64? {
        let first = try readUInt8()
        switch first {
        case 0xfb:
            return nil
        case 0xfc:
            return UInt64(try readUInt16())
        case 0xfd:
            return UInt64(try readUInt24())
        case 0xfe:
            return try readUInt64()
        default:
            return UInt64(first)
        }
    }

    public mutating func readLengthEncodedBytes() throws -> Data? {
        guard let length = try readLengthEncodedInteger() else { return nil }
        guard length <= UInt64(Int.max) else { throw MySQLWireError.invalidPacket }
        return try readBytes(Int(length))
    }

    public mutating func readLengthEncodedString() throws -> String? {
        guard let bytes = try readLengthEncodedBytes() else { return nil }
        return String(data: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
    }
}

public enum MySQLWire {
    public static func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    public static func uint24(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff)])
    }

    public static func uint32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff),
        ])
    }

    public static func cstring(_ value: String) -> Data {
        var data = Data(value.utf8)
        data.append(0)
        return data
    }

    public static func lengthEncoded(_ value: Data?) -> Data {
        guard let value else { return Data([0xfb]) }
        var data = lengthEncodedInteger(UInt64(value.count))
        data.append(value)
        return data
    }

    public static func lengthEncoded(_ value: String?) -> Data {
        lengthEncoded(value.map { Data($0.utf8) })
    }

    public static func lengthEncodedInteger(_ value: UInt64) -> Data {
        switch value {
        case 0..<0xfb:
            return Data([UInt8(value)])
        case 0xfb...0xffff:
            var data = Data([0xfc])
            data.append(uint16(UInt16(value)))
            return data
        case 0x10000...0xffffff:
            var data = Data([0xfd])
            data.append(uint24(UInt32(value)))
            return data
        default:
            var data = Data([0xfe])
            data.append(uint64(value))
            return data
        }
    }

    public static func uint64(_ value: UInt64) -> Data {
        var data = Data()
        for index in 0..<8 {
            data.append(UInt8((value >> UInt64(index * 8)) & 0xff))
        }
        return data
    }
}

public struct MySQLCapabilities: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let longPassword = MySQLCapabilities(rawValue: 0x0000_0001)
    public static let connectWithDatabase = MySQLCapabilities(rawValue: 0x0000_0008)
    public static let protocol41 = MySQLCapabilities(rawValue: 0x0000_0200)
    public static let ssl = MySQLCapabilities(rawValue: 0x0000_0800)
    public static let transactions = MySQLCapabilities(rawValue: 0x0000_2000)
    public static let secureConnection = MySQLCapabilities(rawValue: 0x0000_8000)
    public static let multiStatements = MySQLCapabilities(rawValue: 0x0001_0000)
    public static let multiResults = MySQLCapabilities(rawValue: 0x0002_0000)
    public static let pluginAuth = MySQLCapabilities(rawValue: 0x0008_0000)
    public static let connectAttrs = MySQLCapabilities(rawValue: 0x0010_0000)
    public static let pluginAuthLengthEncodedClientData = MySQLCapabilities(rawValue: 0x0020_0000)
    public static let deprecateEOF = MySQLCapabilities(rawValue: 0x0100_0000)
}

public struct MySQLHandshake: Sendable, Equatable {
    public var protocolVersion: UInt8
    public var serverVersion: String
    public var connectionID: UInt32
    public var scramble: Data
    public var capabilities: MySQLCapabilities
    public var characterSet: UInt8
    public var statusFlags: UInt16
    public var authPlugin: String

    public init(
        protocolVersion: UInt8,
        serverVersion: String,
        connectionID: UInt32,
        scramble: Data,
        capabilities: MySQLCapabilities,
        characterSet: UInt8,
        statusFlags: UInt16,
        authPlugin: String
    ) {
        self.protocolVersion = protocolVersion
        self.serverVersion = serverVersion
        self.connectionID = connectionID
        self.scramble = scramble
        self.capabilities = capabilities
        self.characterSet = characterSet
        self.statusFlags = statusFlags
        self.authPlugin = authPlugin
    }

    public static func parse(_ payload: Data) throws -> MySQLHandshake {
        var reader = MySQLByteReader(data: payload)
        let protocolVersion = try reader.readUInt8()
        guard protocolVersion >= 9 else { throw MySQLWireError.invalidHandshake }
        let serverVersion = try reader.readCString()
        let connectionID = try reader.readUInt32()
        let scramblePart1 = try reader.readBytes(8)
        _ = try reader.readUInt8()
        let capabilityLow = try reader.readUInt16()
        guard !reader.isAtEnd else {
            return MySQLHandshake(
                protocolVersion: protocolVersion,
                serverVersion: serverVersion,
                connectionID: connectionID,
                scramble: scramblePart1,
                capabilities: MySQLCapabilities(rawValue: UInt32(capabilityLow)),
                characterSet: 0,
                statusFlags: 0,
                authPlugin: "mysql_native_password"
            )
        }

        let characterSet = try reader.readUInt8()
        let statusFlags = try reader.readUInt16()
        let capabilityHigh = try reader.readUInt16()
        let capabilities = MySQLCapabilities(rawValue: UInt32(capabilityLow) | (UInt32(capabilityHigh) << 16))
        let authLength = Int(try reader.readUInt8())
        _ = try reader.readBytes(10)

        var scramblePart2 = Data()
        if capabilities.contains(.secureConnection) && !reader.isAtEnd {
            let length = max(13, authLength - 8)
            scramblePart2 = try reader.readBytes(min(length, payload.count - reader.offset))
            while scramblePart2.last == 0 { scramblePart2.removeLast() }
        }
        var plugin = "mysql_native_password"
        if capabilities.contains(.pluginAuth), !reader.isAtEnd {
            plugin = try reader.readCString()
        }

        var scramble = scramblePart1
        scramble.append(scramblePart2)
        return MySQLHandshake(
            protocolVersion: protocolVersion,
            serverVersion: serverVersion,
            connectionID: connectionID,
            scramble: Data(scramble.prefix(20)),
            capabilities: capabilities,
            characterSet: characterSet,
            statusFlags: statusFlags,
            authPlugin: plugin
        )
    }
}

public struct MySQLColumnDefinition: Sendable, Equatable {
    public var name: String
    public var tableName: String?
    public var schema: String?
    public var type: UInt8
    public var flags: UInt16
    public var decimals: UInt8

    public init(
        name: String,
        tableName: String?,
        type: UInt8,
        flags: UInt16,
        decimals: UInt8,
        schema: String? = nil
    ) {
        self.name = name
        self.tableName = tableName
        self.schema = schema
        self.type = type
        self.flags = flags
        self.decimals = decimals
    }

    public static func parse(_ payload: Data) throws -> MySQLColumnDefinition {
        var reader = MySQLByteReader(data: payload)
        _ = try reader.readLengthEncodedString()
        let schema = emptyToNil(try reader.readLengthEncodedString())
        let table = emptyToNil(try reader.readLengthEncodedString())
        let orgTable = emptyToNil(try reader.readLengthEncodedString())
        let name = try reader.readLengthEncodedString() ?? ""
        _ = try reader.readLengthEncodedString()
        let fixedLength = try reader.readUInt8()
        guard fixedLength >= 0x0c else { throw MySQLWireError.invalidPacket }
        _ = try reader.readUInt32()
        _ = try reader.readUInt32()
        let type = try reader.readUInt8()
        let flags = try reader.readUInt16()
        let decimals = try reader.readUInt8()
        _ = try reader.readBytes(2)
        return MySQLColumnDefinition(
            name: name,
            tableName: orgTable ?? table,
            type: type,
            flags: flags,
            decimals: decimals,
            schema: schema
        )
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public enum MySQLColumnType {
    public static let decimal: UInt8 = 0
    public static let tiny: UInt8 = 1
    public static let short: UInt8 = 2
    public static let long: UInt8 = 3
    public static let float: UInt8 = 4
    public static let double: UInt8 = 5
    public static let null: UInt8 = 6
    public static let timestamp: UInt8 = 7
    public static let longLong: UInt8 = 8
    public static let int24: UInt8 = 9
    public static let date: UInt8 = 10
    public static let time: UInt8 = 11
    public static let dateTime: UInt8 = 12
    public static let year: UInt8 = 13
    public static let varchar: UInt8 = 15
    public static let bit: UInt8 = 16
    public static let json: UInt8 = 245
    public static let newDecimal: UInt8 = 246
    public static let enumType: UInt8 = 247
    public static let set: UInt8 = 248
    public static let tinyBlob: UInt8 = 249
    public static let mediumBlob: UInt8 = 250
    public static let longBlob: UInt8 = 251
    public static let blob: UInt8 = 252
    public static let varString: UInt8 = 253
    public static let string: UInt8 = 254
    public static let geometry: UInt8 = 255
}
