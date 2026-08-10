import Foundation
import Synchronization

final class PostgresTransport: @unchecked Sendable {
    private final class State: @unchecked Sendable {
        var input: InputStream?
        var output: OutputStream?
        var host = ""
        var closed = false
        var scheduled = false
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "com.sexiql.pg.transport", qos: .userInitiated)

    var connectTimeout: TimeInterval = 20
    var readTimeout: TimeInterval = 30

    func connect(host: String, port: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    var input: InputStream?
                    var output: OutputStream?
                    Stream.getStreamsToHost(withName: host, port: port, inputStream: &input, outputStream: &output)
                    guard let input, let output else {
                        throw PGError(code: "08001", message: "Unable to create TCP streams to \(host):\(port)")
                    }
                    input.schedule(in: .current, forMode: .default)
                    output.schedule(in: .current, forMode: .default)
                    input.open()
                    output.open()
                    try self.waitUntilOpen(
                        input: input,
                        output: output,
                        timeout: self.connectTimeout,
                        stage: "TCP connect to \(host):\(port)"
                    )
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

    func startTLS(serverName: String?, verifyCertificate: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let streams = self.state.withLock { ($0.input, $0.output, $0.host, $0.scheduled) }
                    guard let input = streams.0, let output = streams.1 else {
                        throw PGError(code: "08006", message: "Not connected (TLS upgrade)")
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
                        throw PGError(code: "08006", message: "Unable to enable TLS on Postgres streams")
                    }

                    try self.completeTLSHandshake(
                        input: input,
                        output: output,
                        peer: peer,
                        verifyCertificate: verifyCertificate,
                        timeout: self.connectTimeout
                    )
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
                        throw PGError(code: "08006", message: "Postgres output stream is closed")
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
                        throw PGError(code: "08006", message: "Postgres input stream is closed")
                    }
                    let data = try self.readExactly(count, from: input)
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

    // MARK: - Blocking helpers

    private func waitUntilOpen(
        input: InputStream,
        output: OutputStream,
        timeout: TimeInterval,
        stage: String
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let detail = streamErrorDescription(input: input, output: output) {
                throw PGError(code: "08001", message: "\(stage) failed: \(detail)")
            }
            if input.streamStatus == .open && output.streamStatus == .open {
                return
            }
            if input.streamStatus == .closed || output.streamStatus == .closed {
                throw PGError(code: "08001", message: "\(stage) failed: stream closed")
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        throw PGError(code: "08001", message: "Timed out during \(stage) after \(Int(timeout))s")
    }

    private func completeTLSHandshake(
        input: InputStream,
        output: OutputStream,
        peer: String,
        verifyCertificate: Bool,
        timeout: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var sawSSLContext = false

        while Date() < deadline {
            if let detail = streamErrorDescription(input: input, output: output) {
                throw PGError(
                    code: "08006",
                    message: tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate)
                )
            }
            if input.streamStatus == .error || output.streamStatus == .error {
                let detail = streamErrorDescription(input: input, output: output) ?? "stream error"
                throw PGError(
                    code: "08006",
                    message: tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate)
                )
            }
            if input.streamStatus == .closed || output.streamStatus == .closed {
                throw PGError(
                    code: "08006",
                    message: tlsFailureMessage(
                        detail: "connection closed during handshake",
                        peer: peer,
                        verifyCertificate: verifyCertificate
                    )
                )
            }

            let sslKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLContext as String)
            if input.property(forKey: sslKey) != nil || output.property(forKey: sslKey) != nil {
                sawSSLContext = true
            }

            if sawSSLContext {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                if let detail = streamErrorDescription(input: input, output: output) {
                    throw PGError(
                        code: "08006",
                        message: tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate)
                    )
                }
                return
            }

            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        if let detail = streamErrorDescription(input: input, output: output) {
            throw PGError(
                code: "08006",
                message: tlsFailureMessage(detail: detail, peer: peer, verifyCertificate: verifyCertificate)
            )
        }
        if !sawSSLContext {
            throw PGError(
                code: "08006",
                message: tlsFailureMessage(
                    detail: "TLS context was not established within \(Int(timeout))s",
                    peer: peer,
                    verifyCertificate: verifyCertificate
                )
            )
        }
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
        let deadline = Date().addingTimeInterval(readTimeout)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset < data.count {
                if Date() > deadline {
                    throw PGError(code: "08006", message: "Timed out writing to Postgres server")
                }
                let count = output.write(base.advanced(by: offset), maxLength: data.count - offset)
                if count < 0 {
                    throw output.streamError
                        ?? PGError(code: "08006", message: "Postgres write failed")
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
                throw PGError(
                    code: "08006",
                    message: "Timed out waiting for Postgres server response after \(Int(readTimeout))s"
                )
            }
            let requested = min(buffer.count, count - output.count)
            let read = input.read(&buffer, maxLength: requested)
            if read < 0 {
                throw input.streamError
                    ?? PGError(code: "08006", message: "Postgres read failed")
            }
            if read == 0 {
                if input.streamStatus == .atEnd || input.streamStatus == .closed {
                    throw PGError(code: "08006", message: "Postgres server closed the connection")
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                continue
            }
            output.append(contentsOf: buffer[0..<read])
        }
        return output
    }
}

private extension Stream.Status {
    var isTerminal: Bool {
        self == .closed || self == .atEnd || self == .error
    }
}
