import AppKit
import SwiftUI
import SQLCore

struct TitlebarNavigationControls: NSViewRepresentable {
    @Environment(WorkspaceModel.self) private var model

    func makeNSView(context: Context) -> TitlebarNavigationView {
        let view = TitlebarNavigationView()
        wire(view)
        return view
    }

    func updateNSView(_ nsView: TitlebarNavigationView, context: Context) {
        wire(nsView)
        nsView.reload(
            connections: model.document.connections.map { profile in
                TitlebarNavigationView.ConnectionItem(
                    id: profile.id,
                    title: {
                        let catalog = profile.displayCatalog
                        if catalog.isEmpty { return profile.name }
                        return "\(profile.name) · \(catalog)"
                    }(),
                    subtitle: {
                        let engine = profile.kind.displayName
                        switch model.status(for: profile.id) {
                        case .connected: return "\(engine) · Connected"
                        case .connecting: return "\(engine) · Connecting"
                        case .failed: return "\(engine) · Failed"
                        case .disconnected: return engine
                        }
                    }(),
                    statusColor: {
                        switch model.status(for: profile.id) {
                        case .connected: return .systemGreen
                        case .connecting: return .systemOrange
                        case .failed: return .systemRed
                        case .disconnected: return NSColor.secondaryLabelColor.withAlphaComponent(0.55)
                        }
                    }()
                )
            },
            selectedID: model.selectedTabConnectionID ?? model.selectedConnectionID,
            sidebarVisible: model.sidebarVisible
        )
    }

    private func wire(_ view: TitlebarNavigationView) {
        view.onToggleSidebar = { model.toggleSidebar() }
        view.onSelectConnection = { id in
            if let id,
               let profile = model.document.connections.first(where: { $0.id == id }) {
                model.selectConnection(profile)
                if model.status(for: id) != .connected && model.status(for: id) != .connecting {
                    model.connect(profile)
                }
            } else {
                model.setSelectedTabConnection(nil)
            }
        }
    }
}

final class TitlebarNavigationView: NSView {
    struct ConnectionItem {
        var id: UUID
        var title: String
        var subtitle: String
        var statusColor: NSColor
    }

    var onToggleSidebar: (() -> Void)?
    var onSelectConnection: ((UUID?) -> Void)?

    private let stack = NSStackView()
    private let sidebarEffect = NSVisualEffectView()
    private let sidebarButton = NSButton()
    private let pillEffect = NSVisualEffectView()
    private let pillButton = NSButton()
    private let statusDot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var items: [ConnectionItem] = []
    private var selectedID: UUID?
    private var connectionMenu = NSMenu()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        configureGlass(sidebarEffect, cornerRadius: 14)
        configureGlass(pillEffect, cornerRadius: 14)

        sidebarButton.bezelStyle = .shadowlessSquare
        sidebarButton.isBordered = false
        sidebarButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Sidebar")
        sidebarButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        sidebarButton.imagePosition = .imageOnly
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar)
        sidebarButton.toolTip = "Toggle Sidebar (⌘0)"
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarEffect.addSubview(sidebarButton)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.backgroundColor = .clear
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        chevron.contentTintColor = .secondaryLabelColor
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let pillStack = NSStackView(views: [statusDot, titleLabel, chevron])
        pillStack.orientation = .horizontal
        pillStack.spacing = 6
        pillStack.alignment = .centerY
        pillStack.edgeInsets = NSEdgeInsets(top: 0, left: 9, bottom: 0, right: 8)
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillEffect.addSubview(pillStack)

        pillButton.bezelStyle = .shadowlessSquare
        pillButton.isBordered = false
        pillButton.isTransparent = true
        pillButton.title = ""
        pillButton.image = nil
        pillButton.target = self
        pillButton.action = #selector(showConnectionMenu(_:))
        pillButton.toolTip = "Active connection — also set from the sidebar"
        pillButton.translatesAutoresizingMaskIntoConstraints = false
        pillEffect.addSubview(pillButton)

        stack.addArrangedSubview(sidebarEffect)
        stack.addArrangedSubview(pillEffect)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            sidebarEffect.widthAnchor.constraint(equalToConstant: 28),
            sidebarEffect.heightAnchor.constraint(equalToConstant: 28),
            sidebarButton.leadingAnchor.constraint(equalTo: sidebarEffect.leadingAnchor),
            sidebarButton.trailingAnchor.constraint(equalTo: sidebarEffect.trailingAnchor),
            sidebarButton.topAnchor.constraint(equalTo: sidebarEffect.topAnchor),
            sidebarButton.bottomAnchor.constraint(equalTo: sidebarEffect.bottomAnchor),

            pillEffect.heightAnchor.constraint(equalToConstant: 28),
            statusDot.widthAnchor.constraint(equalToConstant: 6),
            statusDot.heightAnchor.constraint(equalToConstant: 6),
            chevron.widthAnchor.constraint(equalToConstant: 10),

            pillStack.leadingAnchor.constraint(equalTo: pillEffect.leadingAnchor),
            pillStack.trailingAnchor.constraint(equalTo: pillEffect.trailingAnchor),
            pillStack.topAnchor.constraint(equalTo: pillEffect.topAnchor),
            pillStack.bottomAnchor.constraint(equalTo: pillEffect.bottomAnchor),

            pillButton.leadingAnchor.constraint(equalTo: pillEffect.leadingAnchor),
            pillButton.trailingAnchor.constraint(equalTo: pillEffect.trailingAnchor),
            pillButton.topAnchor.constraint(equalTo: pillEffect.topAnchor),
            pillButton.bottomAnchor.constraint(equalTo: pillEffect.bottomAnchor),

            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
        ])

        pillEffect.addSubview(pillButton, positioned: .above, relativeTo: pillStack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        stack.fittingSize
    }

    private func configureGlass(_ view: NSVisualEffectView, cornerRadius: CGFloat) {
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func reload(connections: [ConnectionItem], selectedID: UUID?, sidebarVisible: Bool) {
        self.items = connections
        self.selectedID = selectedID
        sidebarButton.toolTip = sidebarVisible ? "Hide Sidebar (⌘0)" : "Show Sidebar (⌘0)"

        if let selectedID, let match = connections.first(where: { $0.id == selectedID }) {
            titleLabel.stringValue = match.title
            statusDot.layer?.backgroundColor = match.statusColor.cgColor
        } else {
            titleLabel.stringValue = "No connection"
            statusDot.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.45).cgColor
        }

        let menu = NSMenu()
        let none = NSMenuItem(title: "No connection", action: #selector(pickConnection(_:)), keyEquivalent: "")
        none.target = self
        none.representedObject = ""
        none.state = selectedID == nil ? .on : .off
        menu.addItem(none)

        if !connections.isEmpty {
            menu.addItem(.separator())
            for item in connections {
                let row = NSMenuItem(
                    title: "\(item.title)  ·  \(item.subtitle)",
                    action: #selector(pickConnection(_:)),
                    keyEquivalent: ""
                )
                row.target = self
                row.representedObject = item.id.uuidString
                row.state = item.id == selectedID ? .on : .off
                menu.addItem(row)
            }
        }
        self.connectionMenu = menu
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    @objc private func toggleSidebar() {
        onToggleSidebar?()
    }

    @objc private func showConnectionMenu(_ sender: NSButton) {
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        connectionMenu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func pickConnection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if raw.isEmpty {
            onSelectConnection?(nil)
            return
        }
        if let id = UUID(uuidString: raw) {
            onSelectConnection?(id)
        }
    }
}
