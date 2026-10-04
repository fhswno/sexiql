import AppKit
import SwiftUI

public struct SchemaCanvasView: View {
    @Bindable public var viewModel: CanvasViewModel
    public var onCardDragEnd: (() -> Void)?
    public var onOpenTable: ((String) -> Void)?
    public var onAddVirtualRelationship: ((tableID: String, column: String)) -> Void
    public var onDeleteVirtualRelationship: ((CanvasEdge) -> Void)?
    public var edgeNotation: CanvasEdgeNotation
    public var onStateChanged: (() -> Void)?
    public var onCameraChange: ((CGPoint, CGFloat) -> Void)?
    public var scrollCaptureEnabled: Bool = true
    public var isNarrationActive: (() -> Bool)? = nil
    public var onNarrationStep: ((Int) -> Void)? = nil
    public var onNarrationExit: (() -> Void)? = nil

    @State private var lastMagnification: CGFloat?
    @State private var viewportSize: CGSize = .zero
    @State private var marqueeRect: CGRect?
    @State private var marqueeExtend = false
    @State private var lastCardTap: (id: String, time: TimeInterval)?

    public init(
        viewModel: CanvasViewModel,
        edgeNotation: CanvasEdgeNotation = .labels,
        onCardDragEnd: (() -> Void)? = nil,
        onOpenTable: ((String) -> Void)? = nil,
        onAddVirtualRelationship: @escaping ((tableID: String, column: String)) -> Void = { _ in },
        onDeleteVirtualRelationship: ((CanvasEdge) -> Void)? = nil,
        onStateChanged: (() -> Void)? = nil,
        onCameraChange: ((CGPoint, CGFloat) -> Void)? = nil,
        isNarrationActive: (() -> Bool)? = nil,
        onNarrationStep: ((Int) -> Void)? = nil,
        onNarrationExit: (() -> Void)? = nil,
        scrollCaptureEnabled: Bool = true
    ) {
        self.viewModel = viewModel
        self.edgeNotation = edgeNotation
        self.onCardDragEnd = onCardDragEnd
        self.onOpenTable = onOpenTable
        self.onAddVirtualRelationship = onAddVirtualRelationship
        self.onDeleteVirtualRelationship = onDeleteVirtualRelationship
        self.onStateChanged = onStateChanged
        self.onCameraChange = onCameraChange
        self.scrollCaptureEnabled = scrollCaptureEnabled
        self.isNarrationActive = isNarrationActive
        self.onNarrationStep = onNarrationStep
        self.onNarrationExit = onNarrationExit
    }

    private var tablesByID: [String: CanvasTable] {
        Dictionary(viewModel.tables.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var isCompact: Bool { viewModel.density == .compact }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                dotGrid(size: geo.size)
                    .gesture(marqueeGesture)
                ScrollEventCatcher(isEnabled: scrollCaptureEnabled) { delta in
                    viewModel.pan(by: CGSize(width: -delta.width, height: -delta.height))
                }
                CanvasEdgeLayer(
                    edges: viewModel.edges,
                    tables: tablesByID,
                    scale: viewModel.scale,
                    offset: viewModel.offset,
                    selectedEdgeID: viewModel.selectedEdgeID,
                    selectedTableID: viewModel.selectedTableID,
                    selectedTableIDs: viewModel.selectedTableIDs,
                    highlightedTableIDs: viewModel.highlightedTableIDs,
                    filteredOutTableIDs: viewModel.filteredOutTableIDs,
                    hoveredTableID: viewModel.hoveredTableID,
                    hiddenTableIDs: viewModel.hiddenTableIDs,
                    compact: isCompact,
                    notation: edgeNotation,
                    narrationTableIDs: viewModel.narrationTableIDs
                )
                cards(size: geo.size)
                if let marqueeRect {
                    marqueeOverlay(rect: marqueeRect)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    handleCanvasTap(at: value.location)
                }
            )
            .onAppear {
                viewportSize = geo.size
                CanvasDebugLog.log("onAppear viewport=\(viewportSize) pendingFit=\(viewModel.pendingInitialFit)")
                if viewModel.pendingInitialFit {
                    withAnimation(.easeOut(duration: 0.3)) {
                        viewModel.fit(viewport: viewportSize)
                    }
                    viewModel.pendingInitialFit = false
                }
            }
            .onChange(of: geo.size) { _, newSize in
                viewportSize = newSize
                if let armed = viewModel.lastFitViewportSize, armed != newSize {
                    viewModel.fit(viewport: newSize)
                }
            }
            .onChange(of: viewModel.pendingInitialFit) { _, pending in
                CanvasDebugLog.log("pendingInitialFit -> \(pending) viewport=\(viewportSize)")
                if pending {
                    withAnimation(.easeOut(duration: 0.3)) {
                        viewModel.fit(viewport: viewportSize)
                    }
                    viewModel.pendingInitialFit = false
                }
            }
            .onChange(of: viewModel.tables.isEmpty) { wasEmpty, isEmpty in
                if wasEmpty, !isEmpty {
                    viewModel.fit(viewport: viewportSize)
                }
            }
            .onChange(of: viewModel.narrationTableIDs) { _, ids in
                guard let ids, !ids.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    viewModel.focusOnTables(ids: Array(ids), viewport: viewportSize)
                }
            }
        }
        .background(.windowBackground)
        .overlay(alignment: .topLeading) { listPanel.padding(14) }
        .overlay(alignment: .top) { virtualEdgeBanner.padding(.top, 10) }
        .overlay(alignment: .bottomTrailing) {
            zoomPill.padding(16)
        }
        .overlay(alignment: .bottomLeading) {
            if viewModel.tables.count >= 6 {
                CanvasMinimapView(
                    tables: viewModel.visibleTables,
                    contentBounds: viewModel.contentBounds,
                    offset: viewModel.offset,
                    scale: viewModel.scale,
                    viewportSize: viewportSize,
                    selectedTableIDs: viewModel.selectedTableIDs,
                    onPan: { world in
                        viewModel.center(onWorld: world, viewport: viewportSize)
                    }
                )
                .padding(16)
            }
        }
        .overlay { CanvasKeyCatcher { keyCode, modifiers in handleKeyEvent(keyCode: keyCode, modifiers: modifiers) } }
        .overlay {
            if viewModel.visibleTables.isEmpty, viewModel.tables.isEmpty {
                emptyState
            }
        }
    }

    // MARK: - Cards

    private func cards(size: CGSize) -> some View {
        ZStack {
            ForEach(viewModel.tables) { table in
                if !viewModel.isHidden(table.id), isVisible(table, viewport: size) {
                    canvasCard(table)
                }
            }
        }
    }

    private func isVisible(_ table: CanvasTable, viewport: CGSize) -> Bool {
        CanvasCanvasInteractionMath.isFrameVisible(
            position: table.position,
            cardWidth: CanvasCardMetrics.cardWidth,
            cardHeight: viewModel.cardHeight(for: table),
            scale: viewModel.scale,
            offset: viewModel.offset,
            viewport: viewport
        )
    }

    private func canvasCard(_ table: CanvasTable) -> some View {
        let width = CanvasCardMetrics.cardWidth * viewModel.scale
        let height = viewModel.cardHeight(for: table) * viewModel.scale
        return CanvasTableCard(
            table: table,
            compact: isCompact,
            onAddVirtualRelationship: { column in
                onAddVirtualRelationship((tableID: table.id, column: column))
            }
        )
        .scaleEffect(viewModel.scale, anchor: .topLeading)
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay {
            if viewModel.selectedTableID == table.id || viewModel.selectedTableIDs.contains(table.id) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .position(
            x: viewModel.offset.width + table.position.x * viewModel.scale + width / 2,
            y: viewModel.offset.height + table.position.y * viewModel.scale + height / 2
        )
        .opacity(dimmed(for: table))
        .highPriorityGesture(cardDragGesture(id: table.id))
        .pointerStyle(.grabIdle)
        .contextMenu {
            Button {
                onOpenTable?(table.id)
            } label: {
                Label("Open \(table.name)", systemImage: "tablecells")
            }
            Button(role: .destructive) {
                viewModel.hideTable(id: table.id)
                onStateChanged?()
            } label: {
                Label("Hide from canvas", systemImage: "eye.slash")
            }
        }
    }

    private func notifyCamera() {
        onCameraChange?(viewModel.cameraWorldCenter(viewport: viewportSize), viewModel.scale)
    }

    private func fitNow() {
        guard viewModel.pendingInitialFit else { return }
        let size = viewModel.lastViewportSize
        guard size.width > 1, size.height > 1 else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            viewModel.fit(viewport: size)
        }
        viewModel.pendingInitialFit = false
    }

    private func dimmed(for table: CanvasTable) -> Double {
        if !viewModel.matchesFilter(table) {
            return 0.12
        }
        if let narration = viewModel.narrationTableIDs {
            return narration.contains(table.id) ? 1 : 0.25
        }
        if !viewModel.selectedTableIDs.isEmpty {
            return viewModel.selectedTableIDs.contains(table.id) ? 1 : 0.45
        }
        if let selected = viewModel.selectedTableID {
            return selected == table.id ? 1 : 0.45
        }
        return 1
    }

    private func cardDragGesture(id: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                for dragID in viewModel.dragGroup(for: id) {
                    viewModel.updateTableDrag(id: dragID, translation: value.translation)
                }
            }
            .onEnded { value in
                for dragID in viewModel.dragGroup(for: id) {
                    viewModel.endTableDrag(id: dragID)
                }
                onCardDragEnd?()
            }
    }

    // MARK: - Gestures

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                marqueeExtend = NSEvent.modifierFlags.contains(.shift)
                marqueeRect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
            }
            .onEnded { _ in
                defer { marqueeRect = nil }
                guard let rect = marqueeRect, rect.width > 4, rect.height > 4 else { return }
                let worldRect = CGRect(
                    x: (rect.minX - viewModel.offset.width) / viewModel.scale,
                    y: (rect.minY - viewModel.offset.height) / viewModel.scale,
                    width: rect.width / viewModel.scale,
                    height: rect.height / viewModel.scale
                )
                viewModel.selectTables(inWorldRect: worldRect, extend: marqueeExtend)
            }
    }

    private func marqueeOverlay(rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.08))
            .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if let last = lastMagnification {
                    viewModel.zoom(by: value.magnification / last)
                }
                lastMagnification = value.magnification
            }
            .onEnded { _ in
                lastMagnification = nil
            }
    }

    private func handleCanvasTap(at location: CGPoint) {
        for table in viewModel.tables.reversed() {
            guard !viewModel.isHidden(table.id) else { continue }
            let frame = CGRect(
                x: table.position.x * viewModel.scale + viewModel.offset.width,
                y: table.position.y * viewModel.scale + viewModel.offset.height,
                width: CanvasCardMetrics.cardWidth * viewModel.scale,
                height: viewModel.cardHeight(for: table) * viewModel.scale
            )
            guard frame.contains(location) else { continue }
            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastCardTap, last.id == table.id, now - last.time < NSEvent.doubleClickInterval {
                lastCardTap = nil
                onOpenTable?(table.id)
                return
            }
            lastCardTap = (table.id, now)
            viewModel.select(table: table.id)
            return
        }
        lastCardTap = nil
        if viewModel.selectedTableID != nil
            || !viewModel.selectedTableIDs.isEmpty
            || viewModel.selectedEdgeID != nil {
            viewModel.clearSelection()
            return
        }
        let world = CGPoint(
            x: (location.x - viewModel.offset.width) / viewModel.scale,
            y: (location.y - viewModel.offset.height) / viewModel.scale
        )
        if let edge = nearestEdge(to: world, threshold: 6 / viewModel.scale) {
            if edge.id == viewModel.selectedEdgeID {
                viewModel.clearSelection()
            } else {
                viewModel.select(edge: edge.id)
            }
        } else {
            viewModel.clearSelection()
        }
    }

    private func nearestEdge(to world: CGPoint, threshold: Double) -> CanvasEdge? {
        var bestEdge: CanvasEdge?
        var bestDistance = Double.greatestFiniteMagnitude
        for edge in viewModel.edges {
            guard !viewModel.isHidden(edge.fromTableID), !viewModel.isHidden(edge.toTableID) else { continue }
            guard let anchors = CanvasEdgeGeometry.anchors(for: edge, tables: tablesByID, compact: isCompact) else { continue }
            let samples = CanvasEdgeGeometry.samplePoints(
                from: anchors.start,
                to: anchors.end,
                isLoop: edge.fromTableID == edge.toTableID
            )
            for sample in samples {
                let dx = sample.x - world.x
                let dy = sample.y - world.y
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < threshold, distance < bestDistance {
                    bestEdge = edge
                    bestDistance = distance
                }
            }
        }
        return bestEdge
    }

    // MARK: - Keyboard

    private func handleKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard !viewModel.visibleTables.isEmpty else { return false }
        let shift = modifiers.contains(.shift)
        let narrating = isNarrationActive?() ?? false

        switch keyCode {
        case 123:
            if narrating {
                onNarrationStep?(-1)
                return true
            }
            stepFocus(.left, extend: shift)
            return true
        case 124:
            if narrating {
                onNarrationStep?(1)
                return true
            }
            stepFocus(.right, extend: shift)
            return true
        case 126:
            stepFocus(.up, extend: shift)
            return true
        case 125:
            stepFocus(.down, extend: shift)
            return true
        case 36, 76:
            if narrating, viewModel.narrationTableIDs?.count == 1,
               let only = viewModel.narrationTableIDs?.first {
                onOpenTable?(only)
                return true
            }
            if let selected = viewModel.selectedTableID {
                onOpenTable?(selected)
                return true
            }
            return false
        case 53:
            if narrating {
                onNarrationExit?()
                return true
            }
            viewModel.clearSelection()
            return true
        default:
            return false
        }
    }

    private func stepFocus(_ direction: CanvasCanvasInteractionMath.FocusDirection, extend: Bool) {
        let anchor = viewModel.selectedTableID ?? viewModel.visibleTables.first?.id
        guard let anchor else { return }
        let previousSelection = viewModel.selectedTableIDs
        viewModel.moveFocus(from: anchor, direction: direction)
        if extend, let moved = viewModel.selectedTableID {
            viewModel.selectedTableIDs = previousSelection.union([moved])
            viewModel.selectedEdgeID = nil
        }
        if let focused = viewModel.selectedTableID {
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.focus(tableID: focused, viewport: viewportSize)
            }
        }
    }

    // MARK: - Chrome

    private func dotGrid(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let spacing = 26.0 * viewModel.scale
            guard spacing > 9 else { return }
            let offsetX = viewModel.offset.width.truncatingRemainder(dividingBy: spacing)
            let offsetY = viewModel.offset.height.truncatingRemainder(dividingBy: spacing)
            var x = offsetX - spacing
            while x < canvasSize.width + spacing {
                var y = offsetY - spacing
                while y < canvasSize.height + spacing {
                    let dot = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                    context.fill(Path(ellipseIn: dot), with: .color(.primary.opacity(0.07)))
                    y += spacing
                }
                x += spacing
            }
        }
    }


    private var zoomPill: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.setDensity(isCompact ? .full : .compact)
                }
                onStateChanged?()
            } label: {
                Image(systemName: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
            }
            .pointerStyle(.link)
            .help(isCompact ? "Show full table details" : "Compact tables")
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { viewModel.zoomOut() }
            } label: {
                Image(systemName: "minus")
            }
            .pointerStyle(.link)
            .help("Zoom out")
            Text("\(Int((viewModel.scale * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 38)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { viewModel.zoomIn() }
            } label: {
                Image(systemName: "plus")
            }
            .pointerStyle(.link)
            .help("Zoom in")
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)
            Button {
                withAnimation(.easeOut(duration: 0.3)) { viewModel.fit(viewport: viewportSize) }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .pointerStyle(.link)
            .help("Zoom to fit")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private var listPanel: some View {
        CanvasTableListPanel(
            filter: $viewModel.searchFilter,
            tables: viewModel.tables,
            hiddenTables: Array(viewModel.hiddenTableIDs),
            onShow: { viewModel.showTable(id: $0) },
            onShowAll: { viewModel.showAllTables() },
            onSelect: { tableID in
                withAnimation(.easeOut(duration: 0.3)) {
                    viewModel.focus(tableID: tableID, viewport: viewportSize)
                }
            }
        )
    }

    private var virtualEdgeBanner: some View {
        Group {
            if let edge = viewModel.edges.first(where: { $0.id == viewModel.selectedEdgeID }), edge.isVirtual {
                HStack(spacing: 10) {
                    Text("Virtual relationship")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Delete") {
                        onDeleteVirtualRelationship?(edge)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointerStyle(.link)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                Text("Loading schema…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.loadError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            } else {
                Image(systemName: "flowchart")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text("No tables found")
                    .font(.title3)
                Text("This database has no tables to visualize.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
}
