import Foundation
import CryptoKit
import CommonCrypto

public struct SCRAMClient: Sendable, Equatable {
    public struct ServerFirst: Sendable, Equatable {
        public var nonce: String
        public var salt: Data
        public var iterations: Int
    }

    public let username: String
    public let password: String
    public let clientNonce: String
    public let clientFirstMessageBare: String

    public init(username: String, password: String, clientNonce: String? = nil) {
        self.username = username
        self.password = password
        self.clientNonce = clientNonce ?? SCRAMClient.generateNonce()
        self.clientFirstMessageBare = "n=\(Self.escape(username)),r=\(self.clientNonce)"
    }

    public func clientFirstMessage() -> String {
        "n,," + clientFirstMessageBare
    }

    public static func parseServerFirst(_ message: String) throws -> ServerFirst {
        var nonce: String?
        var salt: Data?
        var iterations: Int?
        for part in message.split(separator: ",") {
            if part.hasPrefix("r=") {
                nonce = String(part.dropFirst(2))
            } else if part.hasPrefix("s=") {
                guard let data = Data(base64Encoded: String(part.dropFirst(2))) else {
                    throw PGWireError.invalidMessage
                }
                salt = data
            } else if part.hasPrefix("i=") {
                iterations = Int(part.dropFirst(2))
            }
        }
        guard let nonce, let salt, let iterations, iterations > 0 else {
            throw PGWireError.invalidMessage
        }
        return ServerFirst(nonce: nonce, salt: salt, iterations: iterations)
    }

    public func clientFinalMessage(serverFirst: ServerFirst) throws -> (clientFinal: String, serverSignature: Data) {
        let clientFinalWithoutProof = "c=biws,r=\(serverFirst.nonce)"
        let serverFirstRaw = "r=\(serverFirst.nonce),s=\(serverFirst.salt.base64EncodedString()),i=\(serverFirst.iterations)"
        let authMessage = clientFirstMessageBare + "," + serverFirstRaw + "," + clientFinalWithoutProof

        guard let saltedPassword = pbkdf2SHA256(
            password: password,
            salt: serverFirst.salt,
            iterations: serverFirst.iterations
        ) else {
            throw PGWireError.invalidMessage
        }

        let clientKey = hmacSHA256(key: saltedPassword, data: Data("Client Key".utf8))
        let storedKey = Data(SHA256.hash(data: clientKey))
        let clientSignature = hmacSHA256(key: storedKey, data: Data(authMessage.utf8))
        let clientProof = xor(clientKey, clientSignature)
        let clientFinal = clientFinalWithoutProof + ",p=" + clientProof.base64EncodedString()

        let serverKey = hmacSHA256(key: saltedPassword, data: Data("Server Key".utf8))
        let serverSignature = hmacSHA256(key: serverKey, data: Data(authMessage.utf8))

        return (clientFinal, serverSignature)
    }

    public static func verifyServerFinal(_ serverFinal: String, expected: Data) -> Bool {
        guard serverFinal.hasPrefix("v="),
              let received = Data(base64Encoded: String(serverFinal.dropFirst(2))) else {
            return false
        }
        return received == expected
    }

    private static func escape(_ username: String) -> String {
        username.replacingOccurrences(of: "=", with: "=3D").replacingOccurrences(of: ",", with: "=2C")
    }

    private static func generateNonce() -> String {
        let bytes = (0..<18).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    private func pbkdf2SHA256(password: String, salt: Data, iterations: Int) -> Data? {
        var derived = [UInt8](repeating: 0, count: 32)
        let status = password.withCString { passwordPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr,
                    password.utf8.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived,
                    derived.count
                )
            }
        }
        return status == kCCSuccess ? Data(derived) : nil
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
    }

    private func xor(_ lhs: Data, _ rhs: Data) -> Data {
        Data(zip(lhs, rhs).map { $0 ^ $1 })
    }
}

public func pgMD5Password(password: String, username: String, salt: Data) -> String {
    let inner = md5Hex(password + username)
    var input = Data(inner.utf8)
    input.append(salt)
    return "md5" + md5Hex(String(decoding: input, as: UTF8.self))
}

private func md5Hex(_ string: String) -> String {
    let digest = Insecure.MD5.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
