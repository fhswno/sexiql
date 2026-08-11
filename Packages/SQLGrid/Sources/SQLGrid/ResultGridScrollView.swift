import AppKit

public final class ResultGridScrollView: NSScrollView {
    public let grid = ResultGridView()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        contentView.drawsBackground = true
        contentView.backgroundColor = .textBackgroundColor
        documentView = grid
        grid.configureChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func pinDocument() {
        grid.sizeLastColumnToFit()
    }
}
