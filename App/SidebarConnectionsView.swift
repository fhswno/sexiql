import SwiftUI
import SQLCore
import SQLDrivers
import SQLUI

struct SidebarConnectionsView: View {
    @Environment(WorkspaceModel.self) private var model
    @State private var draggingConnectionID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChromeSectionHeader(title: "Connections") {
                Button {
                    model.editingProfile = nil
                    model.showingConnectionEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Add connection")
            }

            if model.document.connections.isEmpty {
                EmptyStateView(
                    title: "No connections",
                    subtitle: "Add a database connection to start querying.",
                    systemImage: "externaldrive.badge.plus",
                    actionTitle: "Add Connection"
                ) {
                    model.editingProfile = nil
                    model.showingConnectionEditor = true
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: SexiQLSpace.xxs) {
                        ForEach(model.document.connections) { connection in
                            let isDragging = draggingConnectionID == connection.id
                            Group {
                                if isDragging {
                                    dropSlot
                                } else {
                                    connectionRow(connection)
                                }
                            }
                            .onDrag {
                                draggingConnectionID = connection.id
                                return NSItemProvider(object: connection.id.uuidString as NSString)
                            } preview: {
                                dragPreview(connection)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: reorderDelegate(targetID: connection.id)
                            )
                        }
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [.text],
                                delegate: reorderDelegate(targetID: nil)
                            )
                    }
                    .padding(.horizontal, SexiQLSpace.md)
                    .padding(.bottom, SexiQLSpace.lg)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: SexiQLSpace.sm) {
                Image(systemName: "key.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Passwords encrypted on this Mac")
                    .font(SexiQLType.meta)
                    .foregroundStyle(.tertiary)
            }
            .padding(SexiQLSpace.lg)
        }
    }

    private func reorderDelegate(targetID: UUID?) -> ListReorderDropDelegate {
        ListReorderDropDelegate(
            targetID: targetID,
            draggingID: { draggingConnectionID },
            setDraggingID: { draggingConnectionID = $0 },
            move: { dragged, before in
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                    model.moveConnection(id: dragged, before: before)
                }
            }
        )
    }

    private var dropSlot: some View {
        RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
            .fill(SexiQLColors.selectionFill)
            .overlay {
                RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
    }

    private func dragPreview(_ connection: ConnectionProfile) -> some View {
        HStack(spacing: SexiQLSpace.sm) {
            Image(systemName: engineSymbol(connection.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SexiQLColors.engine(connection.kind.rawValue))
            Text(connection.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func connectionRow(_ connection: ConnectionProfile) -> some View {
        let status = model.status(for: connection.id)
        let isSelected = model.selectedConnectionID == connection.id
        let isFailed = if case .failed = status { true } else { false }

        return HStack(spacing: SexiQLSpace.md) {
            Button {
                model.selectConnection(connection)
                if isFailed {
                    model.showConnectionFailure(for: connection)
                }
            } label: {
                HStack(spacing: SexiQLSpace.md) {
                    connectionGlyph(connection, status: status)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.name)
                            .font(.callout.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(connectionSubtitle(connection, status: status))
                            .font(SexiQLType.rowSubtitle)
                            .foregroundStyle(statusForeground(status))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)

                    if isFailed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(SexiQLColors.failed)
                            .help("Show connection error")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(rowHelp(connection, status: status))

            Menu {
                if status == .connected {
                    Button("Disconnect", role: .destructive) {
                        model.requestDisconnect(connection)
                    }
                } else {
                    Button("Connect") {
                        model.connect(connection)
                    }
                }
                if isFailed {
                    Button("Show Error…") {
                        model.showConnectionFailure(for: connection)
                    }
                    Button("Retry") {
                        model.retryConnection(for: connection.id)
                    }
                }
                Divider()
                Button("Edit…") {
                    model.editingProfile = connection
                    model.showingConnectionEditor = true
                }
                Button("Delete", role: .destructive) {
                    model.deleteProfile(connection)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Connection actions")
        }
        .padding(.horizontal, SexiQLSpace.md)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                    .fill(SexiQLColors.selectionFill)
            }
        }
        .contextMenu {
            if status == .connected {
                Button("Disconnect", role: .destructive) {
                    model.requestDisconnect(connection)
                }
            } else {
                Button("Connect") {
                    model.connect(connection)
                }
            }
            if isFailed {
                Button("Show Error…") {
                    model.showConnectionFailure(for: connection)
                }
                Button("Retry") {
                    model.retryConnection(for: connection.id)
                }
            }
            Divider()
            Button("Edit…") {
                model.editingProfile = connection
                model.showingConnectionEditor = true
            }
            Button("Delete", role: .destructive) {
                model.deleteProfile(connection)
            }
        }
    }

    private func rowHelp(_ connection: ConnectionProfile, status: ConnectionManager.SessionStatus) -> String {
        switch status {
        case .failed:
            return model.connectionErrorMessage(for: connection.id) ?? "Connection failed"
        case .connecting:
            return "Connecting…"
        case .connected:
            return "Connected"
        case .disconnected:
            return connection.kind.displayName
        }
    }

    private func connectionGlyph(_ connection: ConnectionProfile, status: ConnectionManager.SessionStatus) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(SexiQLColors.engine(connection.kind.rawValue).opacity(0.16))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: engineSymbol(connection.kind))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SexiQLColors.engine(connection.kind.rawValue))
                }

            ZStack {
                Circle()
                    .fill(.background)
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 7, height: 7)
            }
            .offset(x: 2, y: 2)
        }
    }

    private func engineSymbol(_ kind: DatabaseKind) -> String {
        switch kind {
        case .postgres: "cylinder.split.1x2"
        case .mysql: "server.rack"
        case .sqlite: "internaldrive"
        case .redis: "memorychip"
        }
    }

    private func statusColor(_ status: ConnectionManager.SessionStatus) -> Color {
        switch status {
        case .disconnected: SexiQLColors.disconnected.opacity(0.55)
        case .connecting: SexiQLColors.connecting
        case .connected: SexiQLColors.connected
        case .failed: SexiQLColors.failed
        }
    }

    private func statusForeground(_ status: ConnectionManager.SessionStatus) -> Color {
        switch status {
        case .failed: SexiQLColors.failed
        case .connecting: SexiQLColors.connecting
        default: .secondary
        }
    }

    private func connectionSubtitle(_ connection: ConnectionProfile, status: ConnectionManager.SessionStatus) -> String {
        switch status {
        case .disconnected: return connection.kind.displayName
        case .connecting: return "\(connection.kind.displayName) · connecting…"
        case .connected: return "\(connection.kind.displayName) · connected"
        case .failed: return "\(connection.kind.displayName) · Failed"
        }
    }
}
