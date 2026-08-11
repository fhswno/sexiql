import Darwin
import Foundation
import SQLCore
import Synchronization

public enum TunnelError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration(String)
    case passwordAuthenticationUnavailable
    case processFailed(String)
    case timedOut
    case notImplemented(feature: String)
    case handshakeFailed
    case portForwardFailed

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .passwordAuthenticationUnavailable:
            "Password-based SSH authentication is not supported. Use a key or agent."
        case .processFailed(let message): "SSH failed: \(message)"
        case .timedOut: "SSH tunnel timed out"
        case .notImplemented(let feature): "SSH feature not implemented: \(feature)"
        case .handshakeFailed: "SSH handshake failed"
        case .portForwardFailed: "SSH port forward failed"
        }
    }
}

public protocol TunnelSession: Sendable {
    var localPort: Int { get }
    func stop() async throws
}

public struct SSHCommand: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String = "/usr/bin/ssh", arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum SSHCommandBuilder {
    public static func make(
        ssh: SSHTunnelConfiguration,
        databaseHost: String,
        databasePort: Int,
        localPort: Int
    ) throws -> SSHCommand {
        guard !ssh.host.isEmpty, !ssh.username.isEmpty else {
            throw TunnelError.invalidConfiguration("SSH host and username are required")
        }
        guard !databaseHost.isEmpty, (1...65535).contains(databasePort) else {
            throw TunnelError.invalidConfiguration("Database host and port are required")
        }
        guard (1...65535).contains(localPort) else {
            throw TunnelError.invalidConfiguration("Invalid local forwarding port")
        }
        guard ssh.authentication == .privateKey else {
            throw TunnelError.passwordAuthenticationUnavailable
        }

        var arguments = [
            "-N",
            "-T",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-L", "127.0.0.1:\(localPort):\(databaseHost):\(databasePort)",
            "-p", String(ssh.port),
        ]
        if let privateKeyPath = ssh.privateKeyPath, !privateKeyPath.isEmpty {
            arguments += ["-i", privateKeyPath]
        }
        arguments.append("\(ssh.username)@\(ssh.host)")
        return SSHCommand(arguments: arguments)
    }
}

private final class SSHProcessSession: TunnelSession, @unchecked Sendable {
    let localPort: Int
    private let process: Process
    private let stopped = Mutex(false)

    init(localPort: Int, process: Process) {
        self.localPort = localPort
        self.process = process
    }

    func stop() async throws {
        let shouldStop = stopped.withLock { value in
            guard !value else { return false }
            value = true
            return true
        }
        guard shouldStop else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}

public struct SSHTunnelManager: Sendable {
    public init() {}

    public func makeSession(
        for profile: ConnectionProfile,
        password: String?
    ) async throws -> any TunnelSession {
        guard profile.useSSH, let ssh = profile.ssh else {
            throw TunnelError.invalidConfiguration("SSH tunneling is not enabled for this profile")
        }
        guard ssh.authentication == .privateKey else {
            throw TunnelError.passwordAuthenticationUnavailable
        }
        _ = password

        let localPort = try Self.allocateLocalPort()
        let command = try SSHCommandBuilder.make(
            ssh: ssh,
            databaseHost: profile.host,
            databasePort: profile.port,
            localPort: localPort
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw TunnelError.processFailed(error.localizedDescription)
        }

        let session = SSHProcessSession(localPort: localPort, process: process)
        do {
            try await Self.waitForPort(localPort, process: process)
            return session
        } catch {
            try? await session.stop()
            throw error
        }
    }

    private static func allocateLocalPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TunnelError.portForwardFailed }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw TunnelError.portForwardFailed }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else { throw TunnelError.portForwardFailed }
        return Int(UInt16(bigEndian: bound.sin_port))
    }

    private static func waitForPort(_ port: Int, process: Process) async throws {
        for _ in 0..<100 {
            if !process.isRunning { throw TunnelError.processFailed("ssh exited before the tunnel became ready") }
            if canConnect(to: port) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw TunnelError.timedOut
    }

    private static func canConnect(to port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
