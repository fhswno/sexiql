import Foundation
import Synchronization

protocol MySQLTransporting: Sendable {
    func connect(host: String, port: Int) async throws
    func startTLS(serverName: String?, verifyCertificate: Bool) async throws
    func write(_ data: Data) async throws
    func readPacket(expectedSequence: UInt8) async throws -> MySQLPacket
    func close() async
}

final class MySQLTransport: MySQLTransporting, @unchecked Sendable {
    nonisolated(unsafe) static var debugDump = false

    private final class State: @unchecked Sendable {
        var input: InputStream?
        var output: OutputStream?
        var host = ""
        var closed = false
        var scheduled = false
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "com.sexiql.mysql.transport", qos: .userInitiated)

    func connect(host: String, port: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    var input: InputStream?
                    var output: OutputStream?
                    Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
                    guard let input, let output else {
                        throw MySQLWireError.protocolError("Unable to create MySQL streams")
                    }
                    input.schedule(in: .current, forMode: .default)
                    output.schedule(in: .current, forMode: .default)
                    input.open()
                    output.open()
                    try self.waitUntilOpen(input: input, output: output)
                    self.state.withLock { state in
                        state.input = input
                        state.output = output
                        state.host = host
                        state.closed = false
                        state.scheduled = true
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    func startTLS(serverName: String? = nil, verifyCertificate: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let streams = self.state.withLock { ($0.input, $0.output, $0.host, $0.scheduled) }
                    guard let input = streams.0,
                          let output = streams.1 else {
                        throw MySQLWireError.protocolError("MySQL transport is not connected")
                    }
                    if !streams.3 {
                        input.schedule(in: .current, forMode: .default)
                        output.schedule(in: .current, forMode: .default)
                        self.state.withLock { $0.scheduled = true }
                    }
                    let peer = serverName ?? streams.2
                    var settings: [String: Any] = [
                        kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelNegotiatedSSL,
                    ]
                    if verifyCertificate {
                        settings[kCFStreamSSLValidatesCertificateChain as String] = true
                        settings[kCFStreamSSLPeerName as String] = peer
                    } else {
                        settings[kCFStreamSSLValidatesCertificateChain as String] = false
                        settings[kCFStreamSSLPeerName as String] = kCFNull as Any
                    }
                    let key = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)
                    guard input.setProperty(settings, forKey: key),
                          output.setProperty(settings, forKey: key) else {
                        throw MySQLWireError.protocolError("Unable to enable MySQL TLS")
                    }
                    try self.completeTLSHandshake(input: input, output: output, peer: peer, verifyCertificate: verifyCertificate)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard let output = self.state.withLock({ $0.output }), !output.streamStatus.isTerminal else {
                        throw MySQLWireError.protocolError("MySQL output stream is closed")
                    }
                    try self.write(data, to: output)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func readPacket(expectedSequence: UInt8) async throws -> MySQLPacket {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MySQLPacket, Error>) in
            queue.async {
                do {
                    guard let input = self.state.withLock({ $0.input }), !input.streamStatus.isTerminal else {
                        throw MySQLWireError.protocolError("MySQL input stream is closed")
                    }
                    var payload = Data()
                    var nextSequence = expectedSequence
                    var sequence = expectedSequence
                    while true {
                        let header = try self.readExactly(4, from: input)
                        let length = Int(header[0]) | (Int(header[1]) << 8) | (Int(header[2]) << 16)
                        sequence = header[3]
                        guard sequence == nextSequence else {
                            throw MySQLWireError.protocolError("Unexpected MySQL packet sequence \(sequence)")
                        }
                        let part = try self.readExactly(length, from: input)
                        guard payload.count <= Self.maximumMessageSize - part.count else {
                            throw MySQLWireError.protocolError("MySQL response is too large")
                        }
                        payload.append(part)
                        if length < 0xFF_FFFF { break }
                        nextSequence = sequence &+ 1
                    }
                    if Self.debugDump {
                        let hex = payload.prefix(48).map { String(format: "%02x", $0) }.joined(separator: " ")
                        print("MySQLTransport ← seq \(sequence) len \(payload.count): \(hex)")
                    }
                    continuation.resume(returning: MySQLPacket(sequence: sequence, payload: payload))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.state.withLock { state in
                    if state.scheduled {
                        state.input?.remove(from: .current, forMode: .default)
                        state.output?.remove(from: .current, forMode: .default)
                        state.scheduled = false
                    }
                    state.input?.close()
                    state.output?.close()
                    state.input = nil
                    state.output = nil
                    state.closed = true
                }
                continuation.resume()
            }
        }
    }

    private func waitUntilOpen(input: InputStream, output: OutputStream) throws {
        var attempts = 0
        while attempts < 500 {
            if input.streamStatus == .open && output.streamStatus == .open { return }
            if input.streamStatus == .error || output.streamStatus == .error {
                throw MySQLWireError.protocolError(input.streamError?.localizedDescription ?? output.streamError?.localizedDescription ?? "MySQL stream failed")
            }
            if input.streamStatus == .closed || output.streamStatus == .closed {
                throw MySQLWireError.protocolError("MySQL stream closed while opening")
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            attempts += 1
        }
        throw MySQLWireError.protocolError("Timed out opening MySQL stream")
    }

    private func completeTLSHandshake(input: InputStream, output: OutputStream, peer: String, verifyCertificate: Bool) throws {
        let deadline = Date().addingTimeInterval(10)
        var sawSSLContext = false
        let sslKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLContext as String)
        while Date() < deadline {
            if let detail = streamErrorDescription(input: input, output: output) {
                throw MySQLWireError.protocolError(tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate))
            }
            if input.streamStatus == .error || output.streamStatus == .error {
                let detail = streamErrorDescription(input: input, output: output) ?? "stream error"
                throw MySQLWireError.protocolError(tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate))
            }
            if input.streamStatus == .closed || output.streamStatus == .closed {
                throw MySQLWireError.protocolError(tlsFailureMessage(detail: "connection closed during handshake", peer: peer, verifyCertificate: verifyCertificate))
            }
            if input.property(forKey: sslKey) != nil || output.property(forKey: sslKey) != nil {
                sawSSLContext = true
            }
            if sawSSLContext {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                if let detail = streamErrorDescription(input: input, output: output) {
                    throw MySQLWireError.protocolError(tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate))
                }
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if let detail = streamErrorDescription(input: input, output: output) {
            throw MySQLWireError.protocolError(tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate))
        }
        throw MySQLWireError.protocolError(tlsFailureMessage(detail: "TLS context was not established within 10s", peer: peer, verifyCertificate: verifyCertificate))
    }

    private func tlsFailureMessage(detail: String, peer: String, verifyCertificate: Bool) -> String {
        let verify = verifyCertificate ? "verify-full" : "encrypt-only (no cert verify)"
        return "TLS handshake failed with \(peer) [\(verify)]: \(detail)"
    }

    private func streamErrorDescription(input: InputStream, output: OutputStream) -> String? {
        if let error = input.streamError {
            return error.localizedDescription
        }
        if let error = output.streamError {
            return error.localizedDescription
        }
        return nil
    }

    private func write(_ data: Data, to output: OutputStream) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = output.write(base.advanced(by: offset), maxLength: data.count - offset)
                if count < 0 {
                    throw output.streamError ?? MySQLWireError.protocolError("MySQL write failed")
                }
                if count == 0 {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                    continue
                }
                offset += count
            }
        }
    }

    private func readExactly(_ count: Int, from input: InputStream) throws -> Data {
        guard count >= 0, count <= Self.maximumPacketSize else {
            throw MySQLWireError.protocolError("MySQL packet is too large")
        }
        var output = Data()
        output.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: min(count, 64 * 1024))
        let deadline = Date().addingTimeInterval(30)
        while output.count < count {
            if Date() > deadline {
                throw MySQLWireError.protocolError("Timed out waiting for MySQL server response after 30s")
            }
            let requested = min(buffer.count, count - output.count)
            let read = input.read(&buffer, maxLength: requested)
            if read < 0 {
                throw input.streamError ?? MySQLWireError.protocolError("MySQL read failed")
            }
            if read == 0 {
                if input.streamStatus == .atEnd || input.streamStatus == .closed {
                    throw MySQLWireError.protocolError("MySQL server closed the connection")
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                continue
            }
            output.append(contentsOf: buffer[0..<read])
        }
        return output
    }

    private static let maximumPacketSize = 0xFF_FFFF
    private static let maximumMessageSize = 1024 * 1024 * 1024
}

private extension Stream.Status {
    var isTerminal: Bool {
        self == .closed || self == .atEnd || self == .error
    }
}
