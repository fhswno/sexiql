import Foundation

public struct ConnectionURLComponents: Sendable, Equatable {
    public var kind: DatabaseKind?
    public var host: String?
    public var port: Int?
    public var database: String?
    public var username: String?
    public var password: String?
    public var tlsMode: TLSMode?

    public init(
        kind: DatabaseKind? = nil,
        host: String? = nil,
        port: Int? = nil,
        database: String? = nil,
        username: String? = nil,
        password: String? = nil,
        tlsMode: TLSMode? = nil
    ) {
        self.kind = kind
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.password = password
        self.tlsMode = tlsMode
    }
}

public enum ConnectionURLParser {
    public static func parse(_ raw: String) -> ConnectionURLComponents? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if looksLikeURL(trimmed), let components = parseURLString(trimmed) {
            return components
        }
        return nil
    }

    public static func looksLikeURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("postgres://") || lower.hasPrefix("postgresql://") { return true }
        if lower.hasPrefix("mysql://") || lower.hasPrefix("mysql2://") { return true }
        if lower.hasPrefix("sqlite://") || lower.hasPrefix("sqlite:") || lower.hasPrefix("file:") { return true }
        if lower.hasPrefix("redis://") || lower.hasPrefix("rediss://") { return true }
        if lower.hasPrefix("jdbc:postgresql:") || lower.hasPrefix("jdbc:mysql:") { return true }
        if trimmed.contains("://") { return true }
        return false
    }

    private static func parseURLString(_ raw: String) -> ConnectionURLComponents? {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if working.lowercased().hasPrefix("jdbc:") {
            working = String(working.dropFirst(5))
        }

        let lower = working.lowercased()
        if lower.hasPrefix("sqlite:") || lower.hasPrefix("file:") {
            return parseSQLite(working)
        }

        guard let url = URL(string: working) else {
            return parseManually(working)
        }

        guard let scheme = url.scheme?.lowercased() else { return nil }
        var components = ConnectionURLComponents()

        switch scheme {
        case "postgres", "postgresql":
            components.kind = .postgres
        case "mysql", "mysql2":
            components.kind = .mysql
        case "redis":
            components.kind = .redis
            if components.tlsMode == nil { components.tlsMode = .off }
        case "rediss":
            components.kind = .redis
            if components.tlsMode == nil { components.tlsMode = .required }
        case "sqlite", "file":
            return parseSQLite(working)
        default:
            break
        }

        if let host = url.host, !host.isEmpty {
            components.host = host
        } else if let host = manualHost(from: working) {
            components.host = host
        }

        if let port = url.port {
            components.port = port
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty {
            components.database = path.removingPercentEncoding ?? path
        }

        if let user = url.user, !user.isEmpty {
            components.username = user.removingPercentEncoding ?? user
        }
        if let password = url.password {
            components.password = password.removingPercentEncoding ?? password
        }

        if components.username == nil || (working.contains("@") && components.password == nil) {
            if let userInfo = manualUserInfo(from: working) {
                if components.username == nil { components.username = userInfo.user }
                if components.password == nil { components.password = userInfo.password }
            }
        }

        if let query = URLComponents(string: working)?.queryItems {
            applyQueryItems(query, to: &components)
        }

        guard components.host != nil || components.database != nil || components.username != nil else {
            return nil
        }
        return components
    }

    private static func parseSQLite(_ raw: String) -> ConnectionURLComponents? {
        var path = raw
        let lower = path.lowercased()
        if lower.hasPrefix("sqlite://") {
            path = String(path.dropFirst("sqlite://".count))
        } else if lower.hasPrefix("sqlite:") {
            path = String(path.dropFirst("sqlite:".count))
        } else if lower.hasPrefix("file://") {
            path = String(path.dropFirst("file://".count))
        } else if lower.hasPrefix("file:") {
            path = String(path.dropFirst("file:".count))
        }
        while path.hasPrefix("//") {
            path = String(path.dropFirst())
        }
        if path.hasPrefix("/") == false, raw.lowercased().contains(":///...") {
            // no-op
        }
        path = path.removingPercentEncoding ?? path
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return ConnectionURLComponents(kind: .sqlite, database: path)
    }

    private static func applyQueryItems(_ items: [URLQueryItem], to components: inout ConnectionURLComponents) {
        for item in items {
            let name = item.name.lowercased()
            let value = item.value ?? ""
            switch name {
            case "sslmode", "ssl":
                switch value.lowercased() {
                case "disable", "allow", "false", "0", "off":
                    components.tlsMode = .off
                case "prefer", "preferred":
                    components.tlsMode = .preferred
                case "require", "true", "1", "on":
                    components.tlsMode = .required
                case "verify-ca", "verify-full":
                    components.tlsMode = .verifyFull
                default:
                    break
                }
            case "sslrootcert", "sslcert":
                if components.tlsMode == nil { components.tlsMode = .verifyFull }
            default:
                break
            }
        }
    }

    private static func parseManually(_ raw: String) -> ConnectionURLComponents? {
        guard let schemeRange = raw.range(of: "://") else { return nil }
        let scheme = raw[..<schemeRange.lowerBound].lowercased()
        var rest = String(raw[schemeRange.upperBound...])

        var components = ConnectionURLComponents()
        switch scheme {
        case "postgres", "postgresql": components.kind = .postgres
        case "mysql", "mysql2": components.kind = .mysql
        case "redis":
            components.kind = .redis
            components.tlsMode = .off
        case "rediss":
            components.kind = .redis
            components.tlsMode = .required
        default: break
        }

        if let at = rest.lastIndex(of: "@") {
            let userInfo = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
            if let colon = userInfo.firstIndex(of: ":") {
                components.username = String(userInfo[..<colon]).removingPercentEncoding
                components.password = String(userInfo[userInfo.index(after: colon)...]).removingPercentEncoding
            } else {
                components.username = userInfo.removingPercentEncoding
            }
        }

        let pathSplit = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        var hostPort = String(pathSplit[0])
        if hostPort.contains("?") {
            hostPort = String(hostPort.split(separator: "?", maxSplits: 1)[0])
        }

        if hostPort.hasPrefix("[") {
            if let close = hostPort.firstIndex(of: "]") {
                components.host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
                let after = hostPort[hostPort.index(after: close)...]
                if after.hasPrefix(":"), let port = Int(after.dropFirst()) {
                    components.port = port
                }
            }
        } else if let colon = hostPort.lastIndex(of: ":"),
                  let port = Int(hostPort[hostPort.index(after: colon)...]) {
            components.host = String(hostPort[..<colon])
            components.port = port
        } else if !hostPort.isEmpty {
            components.host = hostPort
        }

        if pathSplit.count > 1 {
            var dbAndQuery = String(pathSplit[1])
            if let q = dbAndQuery.firstIndex(of: "?") {
                let query = String(dbAndQuery[dbAndQuery.index(after: q)...])
                dbAndQuery = String(dbAndQuery[..<q])
                let items = query.split(separator: "&").compactMap { pair -> URLQueryItem? in
                    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    guard let name = parts.first else { return nil }
                    return URLQueryItem(name: name, value: parts.count > 1 ? parts[1] : nil)
                }
                applyQueryItems(items, to: &components)
            }
            if !dbAndQuery.isEmpty {
                components.database = dbAndQuery.removingPercentEncoding ?? dbAndQuery
            }
        }

        guard components.host != nil || components.database != nil else { return nil }
        return components
    }

    private static func manualHost(from raw: String) -> String? {
        parseManually(raw)?.host
    }

    private static func manualUserInfo(from raw: String) -> (user: String?, password: String?)? {
        guard let parsed = parseManually(raw) else { return nil }
        return (parsed.username, parsed.password)
    }
}
