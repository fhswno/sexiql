import Foundation
import SQLCore

enum ConnectionErrorFormatting {
    static func userMessage(technical: String, error: Error?, profile: ConnectionProfile) -> String {
        let raw = bestMessage(technical: technical, error: error)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let endpoint = profile.kind == .sqlite
            ? profile.database
            : "\(profile.host):\(profile.port)"

        if lower.contains("pgerror error") || lower.contains("sqldrivererror error") {
            if let better = (error as? LocalizedError)?.errorDescription, !better.isEmpty {
                return better
            }
        }

        if lower.contains("timed out") || lower.contains("timeout") {
            return """
            Timed out connecting to \(endpoint).
            Check the host, port, VPN, and firewall, then try again.
            """
        }

        if lower.contains("nodename nor servname")
            || lower.contains("hostname could not be found")
            || lower.contains("dns")
            || lower.contains("name or service not known")
            || lower.contains("could not resolve") {
            return """
            Could not resolve host “\(profile.host)”.
            Verify the hostname spelling and your DNS/VPN settings.
            """
        }

        if lower.contains("connection refused") || lower.contains("econnrefused") {
            return """
            Connection refused by \(endpoint).
            Confirm the database is running and the port is correct.
            """
        }

        if lower.contains("network is unreachable") || lower.contains("no route to host") {
            return """
            Network unreachable for \(endpoint).
            Check your network connection, VPN, or SSH tunnel settings.
            """
        }

        if lower.contains("ssl") || lower.contains("tls") || lower.contains("certificate")
            || lower.contains("handshake") {
            let hint: String
            if profile.tlsMode.verifiesCertificate {
                hint = "Certificate verification is on. For RDS/cloud, try TLS “Required” (encrypt only), or install the provider CA."
            } else {
                hint = "Encryption is on without cert verify. Check VPN/network, or try “Verify full” if the server requires a specific CA."
            }
            if raw.localizedCaseInsensitiveContains("TLS handshake failed")
                || raw.localizedCaseInsensitiveContains("ssl") {
                return raw + "\n\n" + hint
            }
            return """
            TLS/SSL handshake failed for \(endpoint).
            \(raw)

            \(hint)
            """
        }

        if lower.contains("password") || lower.contains("authentication") || lower.contains("28p01")
            || lower.contains("access denied") || lower.contains("auth") {
            return """
            Authentication failed for user “\(profile.username)”.
            Check the username and password (and that the password was saved).
            """
        }

        if lower.contains("does not support tls") {
            return """
            Server at \(endpoint) does not support TLS, but TLS is required.
            Set TLS to Off or Preferred, or enable TLS on the server.
            """
        }

        if lower.contains("operation couldn") || lower.contains("operation couldn't") {
            var detail = raw
            if let range = raw.range(of: ".") {
                let after = raw[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty { detail = after }
            }
            return """
            Could not connect to \(endpoint).
            \(detail)
            """
        }

        if raw.isEmpty {
            return "Could not connect to \(endpoint)."
        }

        if raw.count < 220, !lower.hasPrefix("the operation") {
            return raw
        }

        return """
        Could not connect to \(endpoint).
        \(raw)
        """
    }

    private static func bestMessage(technical: String, error: Error?) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        if let error {
            let ns = error as NSError
            if let underlying = ns.userInfo[NSLocalizedDescriptionKey] as? String, !underlying.isEmpty {
                return underlying
            }
            let desc = error.localizedDescription
            if !desc.isEmpty, !desc.contains(" error ") {
                return desc
            }
        }
        if !technical.isEmpty, !technical.contains(" error ") {
            return technical
        }
        if let error {
            return String(describing: error)
        }
        return technical
    }
}
