import XCTest
@testable import SQLTunnel
import SQLCore

final class SSHTunnelTests: XCTestCase {
    func testCommandUsesPrivateKeyAndNoShell() throws {
        let ssh = SSHTunnelConfiguration(
            host: "bastion.example",
            username: "dev",
            authentication: .privateKey,
            privateKeyPath: "/Users/dev/.ssh/id_ed25519"
        )
        let command = try SSHCommandBuilder.make(ssh: ssh, databaseHost: "db.internal", databasePort: 5432, localPort: 49152)
        XCTAssertEqual(command.executable, "/usr/bin/ssh")
        XCTAssertTrue(command.arguments.contains("-N"))
        XCTAssertTrue(command.arguments.contains("-o"))
        XCTAssertTrue(command.arguments.contains("ExitOnForwardFailure=yes"))
        XCTAssertTrue(command.arguments.contains("BatchMode=yes"))
        XCTAssertTrue(command.arguments.contains("127.0.0.1:49152:db.internal:5432"))
        XCTAssertTrue(command.arguments.contains("-i"))
        XCTAssertTrue(command.arguments.contains("/Users/dev/.ssh/id_ed25519"))
        XCTAssertTrue(command.arguments.contains("dev@bastion.example"))
    }

    func testPasswordAuthIsRejectedUntilAskpassIsAudited() {
        let ssh = SSHTunnelConfiguration(host: "bastion", username: "dev", authentication: .password)
        XCTAssertThrowsError(try SSHCommandBuilder.make(ssh: ssh, databaseHost: "db", databasePort: 3306, localPort: 49152)) { error in
            XCTAssertEqual(error as? TunnelError, .passwordAuthenticationUnavailable)
        }
    }

    func testInvalidConfigurationIsRejected() {
        let ssh = SSHTunnelConfiguration(host: "", username: "dev", authentication: .privateKey)
        XCTAssertThrowsError(try SSHCommandBuilder.make(ssh: ssh, databaseHost: "db", databasePort: 3306, localPort: 49152))
        XCTAssertThrowsError(try SSHCommandBuilder.make(ssh: SSHTunnelConfiguration(host: "b", username: "d", authentication: .privateKey), databaseHost: "", databasePort: 3306, localPort: 49152))
        XCTAssertThrowsError(try SSHCommandBuilder.make(ssh: SSHTunnelConfiguration(host: "b", username: "d", authentication: .privateKey), databaseHost: "db", databasePort: 0, localPort: 49152))
    }
}
