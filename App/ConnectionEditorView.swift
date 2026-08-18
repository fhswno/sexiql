import SwiftUI
import SQLCore

struct ConnectionEditorView: View {
    @Environment(WorkspaceModel.self) private var model
    let profile: ConnectionProfile?

    @State private var name: String = ""
    @State private var kind: DatabaseKind = .postgres
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var database: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var tlsMode: TLSMode = .preferred
    @State private var useSSH = false
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUsername = ""
    @State private var privateKeyPath = ""
    @State private var urlPasteHint: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)
                Picker("Engine", selection: $kind) {
                    ForEach(DatabaseKind.allCases) { kind in
                        Text(kind.displayName)
                            .tag(kind)
                    }
                }
                .disabled(profile != nil)
                .onChange(of: kind) { _, newKind in
                    port = newKind.defaultPort == 0 ? "" : String(newKind.defaultPort)
                    if newKind == .redis, tlsMode == .preferred {
                        tlsMode = .off
                    }
                }

                if kind == .sqlite {
                    TextField("Database file path", text: $database)
                } else {
                    TextField("Host", text: $host)
                        .onChange(of: host) { _, newValue in
                            applyConnectionURLIfNeeded(newValue)
                        }
                    if let urlPasteHint {
                        Text(urlPasteHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Port", text: $port)
                        TextField(kind == .redis ? "DB index (0)" : "Database", text: $database)
                    }
                    TextField(kind == .redis ? "ACL username (optional)" : "Username", text: $username)
                    SecureField("Password", text: $password)
                    Picker("TLS", selection: $tlsMode) {
                        Text("Off").tag(TLSMode.off)
                        Text("Preferred (encrypt if available)").tag(TLSMode.preferred)
                        Text("Required (encrypt, no cert verify)").tag(TLSMode.required)
                        Text("Verify full (encrypt + cert)").tag(TLSMode.verifyFull)
                    }
                }

                if kind != .sqlite {
                    Toggle("Use SSH tunnel", isOn: $useSSH)
                    if useSSH {
                        TextField("SSH host", text: $sshHost)
                        HStack {
                            TextField("SSH port", text: $sshPort)
                            TextField("SSH username", text: $sshUsername)
                        }
                        TextField("Private key path (optional; SSH agent otherwise)", text: $privateKeyPath)
                            .font(.caption)
                        Text("Password-based SSH authentication is intentionally disabled in this release. Use an SSH key or agent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    model.showingConnectionEditor = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear(perform: loadFromProfile)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (!(kind == .sqlite) || !database.trimmingCharacters(in: .whitespaces).isEmpty)
            && (kind == .sqlite || !host.trimmingCharacters(in: .whitespaces).isEmpty)
            && (kind == .sqlite || kind == .redis || !username.isEmpty)
            && (!useSSH || (!sshHost.isEmpty && !sshUsername.isEmpty))
    }

    private func loadFromProfile() {
        guard let profile else { return }
        name = profile.name
        kind = profile.kind
        host = profile.host
        port = profile.port > 0 ? String(profile.port) : ""
        database = profile.database
        username = profile.username
        tlsMode = profile.tlsMode
        useSSH = profile.useSSH
        sshHost = profile.ssh?.host ?? ""
        sshPort = profile.ssh.map { String($0.port) } ?? "22"
        sshUsername = profile.ssh?.username ?? ""
        privateKeyPath = profile.ssh?.privateKeyPath ?? ""
    }

    /// When the user pastes a full connection URL into Host, expand it into fields.
    private func applyConnectionURLIfNeeded(_ raw: String) {
        guard ConnectionURLParser.looksLikeURL(raw) else { return }
        guard let parsed = ConnectionURLParser.parse(raw) else {
            urlPasteHint = "Couldn’t parse that connection URL."
            return
        }
        applyParsedURL(parsed)
    }

    private func applyParsedURL(_ parsed: ConnectionURLComponents) {
        if profile == nil, let parsedKind = parsed.kind {
            kind = parsedKind
        }

        if kind == .sqlite {
            if let db = parsed.database {
                database = db
            }
            host = ""
            urlPasteHint = "Parsed SQLite path from URL."
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = (database as NSString).lastPathComponent
            }
            return
        }

        if let h = parsed.host {
            host = h
        }
        if let p = parsed.port {
            port = String(p)
        } else if port.isEmpty, let k = parsed.kind {
            port = String(k.defaultPort)
        }
        if let db = parsed.database {
            database = db
        }
        if let user = parsed.username {
            username = user
        }
        if let pass = parsed.password {
            password = pass
        }
        if let tls = parsed.tlsMode {
            tlsMode = tls
        }

        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            if let db = parsed.database, !db.isEmpty {
                name = db
            } else if let h = parsed.host, !h.isEmpty {
                name = h
            }
        }

        urlPasteHint = "Parsed connection URL into fields."
    }

    private func save() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // Last-chance parse if user somehow still has a URL in host.
        if kind != .sqlite, ConnectionURLParser.looksLikeURL(trimmedHost),
           let parsed = ConnectionURLParser.parse(trimmedHost) {
            applyParsedURL(parsed)
        }

        let resolvedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPort = Int(port) ?? kind.defaultPort
        let saved = ConnectionProfile(
            id: profile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            host: kind == .sqlite ? "" : resolvedHost,
            port: kind == .sqlite ? 0 : resolvedPort,
            database: database.trimmingCharacters(in: .whitespacesAndNewlines),
            username: kind == .sqlite ? "" : username,
            tlsMode: kind == .sqlite ? .off : tlsMode,
            useSSH: kind != .sqlite && useSSH,
            ssh: kind != .sqlite && useSSH
                ? SSHTunnelConfiguration(
                    host: sshHost,
                    port: Int(sshPort) ?? 22,
                    username: sshUsername,
                    authentication: .privateKey,
                    privateKeyPath: privateKeyPath.isEmpty ? nil : privateKeyPath
                )
                : nil
        )
        model.saveProfile(saved, password: password.isEmpty ? nil : password)
        model.showingConnectionEditor = false
    }
}
