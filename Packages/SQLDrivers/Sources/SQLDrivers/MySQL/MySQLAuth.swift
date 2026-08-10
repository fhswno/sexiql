import CryptoKit
import Foundation
import SQLCore

public enum MySQLAuth {
    public static func nativePasswordToken(password: String, scramble: Data) -> Data {
        let passwordHash = Data(Insecure.SHA1.hash(data: Data(password.utf8)))
        let stage2 = Data(Insecure.SHA1.hash(data: passwordHash))
        var challenge = scramble
        challenge.append(stage2)
        let digest = Data(Insecure.SHA1.hash(data: challenge))
        return xor(passwordHash, digest)
    }

    public static func cachingSHA2Token(password: String, scramble: Data) -> Data {
        let passwordHash = Data(SHA256.hash(data: Data(password.utf8)))
        let stage2 = Data(SHA256.hash(data: passwordHash))
        let stage3 = Data(SHA256.hash(data: stage2))
        var challenge = stage3
        challenge.append(scramble)
        let digest = Data(SHA256.hash(data: challenge))
        return xor(passwordHash, digest)
    }

    public static func authToken(password: String, plugin: String, scramble: Data) throws -> Data {
        switch plugin.lowercased() {
        case "mysql_native_password":
            return nativePasswordToken(password: password, scramble: scramble)
        case "caching_sha2_password":
            return cachingSHA2Token(password: password, scramble: scramble)
        default:
            throw MySQLWireError.unsupportedAuthentication(plugin)
        }
    }

    public static func buildCapabilities(
        handshake: MySQLHandshake,
        database: String,
        tlsMode: TLSMode
    ) throws -> MySQLCapabilities {
        guard handshake.capabilities.contains(.protocol41) else {
            throw MySQLWireError.protocolError("MySQL server does not support protocol 4.1")
        }
        var requested: MySQLCapabilities = [
            .longPassword, .protocol41, .secureConnection, .pluginAuth,
            .transactions, .multiResults, .deprecateEOF,
        ]
        if !database.isEmpty { requested.insert(.connectWithDatabase) }
        if tlsMode != .off {
            if handshake.capabilities.contains(.ssl) {
                requested.insert(.ssl)
            } else if tlsMode == .required || tlsMode == .verifyFull {
                throw MySQLWireError.tlsRequired
            }
        }
        return requested.intersection(handshake.capabilities)
    }

    public static func sslRequest(capabilities: MySQLCapabilities, characterSet: UInt8 = 33) -> Data {
        var data = Data()
        data.append(MySQLWire.uint32(capabilities.rawValue))
        data.append(MySQLWire.uint32(16 * 1024 * 1024))
        data.append(characterSet)
        data.append(contentsOf: repeatElement(UInt8(0), count: 23))
        return data
    }

    public static func handshakeResponse(
        username: String,
        database: String,
        passwordToken: Data,
        plugin: String,
        capabilities: MySQLCapabilities,
        characterSet: UInt8 = 33
    ) -> Data {
        var data = Data()
        data.append(MySQLWire.uint32(capabilities.rawValue))
        data.append(MySQLWire.uint32(16 * 1024 * 1024))
        data.append(characterSet)
        data.append(contentsOf: repeatElement(UInt8(0), count: 23))
        data.append(MySQLWire.cstring(username))
        data.append(MySQLWire.lengthEncoded(passwordToken))
        if capabilities.contains(.connectWithDatabase) {
            data.append(MySQLWire.cstring(database))
        }
        if capabilities.contains(.pluginAuth) {
            data.append(MySQLWire.cstring(plugin))
        }
        if capabilities.contains(.connectAttrs) {
            data.append(MySQLWire.lengthEncodedInteger(0))
        }
        return data
    }

    public static func parseError(_ payload: Data) throws -> MySQLWireError {
        var reader = MySQLByteReader(data: payload)
        guard try reader.readUInt8() == 0xff else { throw MySQLWireError.invalidPacket }
        let code = Int(try reader.readUInt16())
        var state: String?
        if !reader.isAtEnd, try reader.readUInt8() == 0x23 {
            state = try reader.readString(5)
        }
        let message = String(decoding: try reader.readBytes(payload.count - reader.offset), as: UTF8.self)
        return .serverError(code: code, message: message, state: state)
    }

    public static func parseOK(_ payload: Data) throws -> (affectedRows: UInt64, lastInsertID: UInt64, status: UInt16) {
        var reader = MySQLByteReader(data: payload)
        let marker = try reader.readUInt8()
        guard marker == 0x00 || marker == 0xfe else { throw MySQLWireError.invalidPacket }
        guard let affected = try reader.readLengthEncodedInteger(),
              let lastID = try reader.readLengthEncodedInteger() else {
            throw MySQLWireError.invalidPacket
        }
        let status = reader.isAtEnd ? 0 : try reader.readUInt16()
        return (affected, lastID, status)
    }

    private static func xor(_ lhs: Data, _ rhs: Data) -> Data {
        Data(zip(lhs, rhs).map { $0 ^ $1 })
    }
}
