import AppKit
import SQLDrivers

// MARK: - Row / Cell Views

final class GridRowView: NSTableRowView {
    static let reuseID = NSUserInterfaceItemIdentifier("grid-row")

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.selectedContentBackgroundColor
            .withAlphaComponent(isEmphasized ? 0.35 : 0.22)
            .setFill()
        bounds.fill()
    }
}

final class GridRowIndexCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(index: Int) {
        label.stringValue = "\(index)"
    }
}

final class GridCellView: NSTableCellView {
    static let normalFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private static let nullFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        .withTraits([.italic])

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = Self.normalFont
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(value: SQLValue, edited: Bool) {
        wantsLayer = true
        if value == .null {
            label.stringValue = "NULL"
            label.font = Self.nullFont
            label.textColor = edited ? .systemOrange : .tertiaryLabelColor
        } else {
            label.stringValue = value.displayString
            label.font = Self.normalFont
            label.textColor = edited ? .systemOrange : .labelColor
        }
        layer?.backgroundColor = edited
            ? NSColor.systemOrange.withAlphaComponent(0.10).cgColor
            : nil
    }
}

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
    }
}
