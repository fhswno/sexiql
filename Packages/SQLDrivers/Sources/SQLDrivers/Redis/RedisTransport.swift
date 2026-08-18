import Foundation
import Synchronization

final class RedisTransport: @unchecked Sendable {
    private final class State: @unchecked Sendable {
        var input: InputStream?
        var output: OutputStream?
        var host = ""
        var closed = false
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "com.sexiql.redis.transport", qos: .userInitiated)
    var readTimeout: TimeInterval = 30

    func connect(host: String, port: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    var input: InputStream?
                    var output: OutputStream?
                    Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
                    guard let input, let output else {
                        throw RedisError.protocolError("Unable to create TCP streams to \(host):\(port)")
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
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startTLS(serverName: String?, verifyCertificate: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let streams = self.state.withLock { ($0.input, $0.output, $0.host) }
                    guard let input = streams.0, let output = streams.1 else {
                        throw RedisError.protocolError("Not connected (TLS upgrade)")
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
                        throw RedisError.protocolError("Unable to enable TLS on Redis streams")
                    }
                    try self.waitUntilOpen(input: input, output: output)
                    if let error = input.streamError ?? output.streamError {
                        throw RedisError.protocolError("TLS handshake failed: \(error.localizedDescription)")
                    }
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
                        throw RedisError.protocolError("Redis output stream is closed")
                    }
                    try self.write(data, to: output)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func readExact(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async {
                do {
                    guard let input = self.state.withLock({ $0.input }), !input.streamStatus.isTerminal else {
                        throw RedisError.protocolError("Redis input stream is closed")
                    }
                    let data = try self.readExactly(count, from: input)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func readSome(max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async {
                do {
                    guard let input = self.state.withLock({ $0.input }), !input.streamStatus.isTerminal else {
                        throw RedisError.protocolError("Redis input stream is closed")
                    }
                    let data = try self.readAvailable(max: max, from: input)
                    continuation.resume(returning: data)
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
                    state.input?.remove(from: .current, forMode: .default)
                    state.output?.remove(from: .current, forMode: .default)
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
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if input.streamStatus == .open && output.streamStatus == .open { return }
            if input.streamStatus == .error || output.streamStatus == .error {
                throw RedisError.protocolError(
                    input.streamError?.localizedDescription
                        ?? output.streamError?.localizedDescription
                        ?? "Redis stream failed"
                )
            }
            if input.streamStatus == .closed || output.streamStatus == .closed {
                throw RedisError.protocolError("Redis stream closed while opening")
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        throw RedisError.protocolError("Timed out opening Redis stream")
    }

    private func write(_ data: Data, to output: OutputStream) throws {
        let deadline = Date().addingTimeInterval(readTimeout)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset < data.count {
                if Date() > deadline {
                    throw RedisError.protocolError("Timed out writing to Redis server")
                }
                let count = output.write(base.advanced(by: offset), maxLength: data.count - offset)
                if count < 0 {
                    if let error = output.streamError {
                        throw RedisError.protocolError("Redis write failed: \(error.localizedDescription)")
                    }
                    if output.streamStatus == .closed || output.streamStatus == .error {
                        throw RedisError.protocolError("Redis write failed")
                    }
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                    continue
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
        var output = Data()
        output.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: min(count, 64 * 1024))
        let deadline = Date().addingTimeInterval(readTimeout)
        while output.count < count {
            if Date() > deadline {
                throw RedisError.protocolError("Timed out waiting for Redis server response")
            }
            let requested = min(buffer.count, count - output.count)
            let read = input.read(&buffer, maxLength: requested)
            if read < 0 {
                throw input.streamError.map { RedisError.protocolError($0.localizedDescription) }
                    ?? RedisError.protocolError("Redis read failed")
            }
            if read == 0 {
                if input.streamStatus == .atEnd || input.streamStatus == .closed {
                    throw RedisError.protocolError("Redis server closed the connection")
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                continue
            }
            output.append(contentsOf: buffer[0..<read])
        }
        return output
    }

    private func readAvailable(max: Int, from input: InputStream) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: Swift.max(max, 1))
        let deadline = Date().addingTimeInterval(readTimeout)
        while true {
            if Date() > deadline {
                throw RedisError.protocolError("Timed out waiting for Redis server response")
            }
            let read = input.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                throw input.streamError.map { RedisError.protocolError($0.localizedDescription) }
                    ?? RedisError.protocolError("Redis read failed")
            }
            if read == 0 {
                if input.streamStatus == .atEnd || input.streamStatus == .closed {
                    throw RedisError.protocolError("Redis server closed the connection")
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                continue
            }
            return Data(buffer[0..<read])
        }
    }
}

private extension Stream.Status {
    var isTerminal: Bool {
        self == .closed || self == .atEnd || self == .error
    }
}
