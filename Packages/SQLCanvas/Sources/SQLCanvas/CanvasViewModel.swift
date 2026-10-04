import SwiftUI

@MainActor
@Observable
public final class CanvasViewModel {
    public private(set) var tables: [CanvasTable] = []
    public private(set) var edges: [CanvasEdge] = []
    public var isLoading = false
    public var loadError: String?
    public private(set) var contentBounds: CGRect = .zero

    public var offset: CGSize = .zero
    public var scale: CGFloat {
        get { _scale }
        set { _scale = min(max(newValue, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) }
    }
    private var _scale: CGFloat = 1
    public var selectedTableID: String?
    public var selectedEdgeID: String?
    public var searchFilter: String = ""
    public var searchFocusToken = 0
    public var pendingInitialFit = false
    public private(set) var lastFitViewportSize: CGSize? = nil
    public var lastViewportSize: CGSize = .zero
    public var selectedTableIDs: Set<String> = []
    public var hoveredTableID: String?
    public private(set) var hiddenTableIDs: Set<String> = []
    public private(set) var density: Density = .full

    public enum Density: String, Sendable {
        case full
        case compact
    }

    public func setDensity(_ newDensity: Density) {
        guard density != newDensity else { return }
        density = newDensity
        recomputeBounds()
    }

    public func isHidden(_ id: String) -> Bool {
        hiddenTableIDs.contains(id)
    }

    public func hideTable(id: String) {
        hiddenTableIDs.insert(id)
        selectedTableIDs.remove(id)
        if selectedTableID == id { selectedTableID = nil }
        recomputeBounds()
    }

    public func showTable(id: String) {
        hiddenTableIDs.remove(id)
        recomputeBounds()
    }

    public func showAllTables() {
        hiddenTableIDs.removeAll()
        recomputeBounds()
    }

    public var visibleTables: [CanvasTable] {
        tables.filter { !hiddenTableIDs.contains($0.id) }
    }

    public func cardHeight(for table: CanvasTable) -> Double {
        switch density {
        case .full:
            return CanvasCardMetrics.tableHeight(columnCount: table.columns.count)
        case .compact:
            return CanvasCardMetrics.headerHeight
        }
    }

    public static let scaleRange: ClosedRange<CGFloat> = 0.25...2.5

    @ObservationIgnored private var dragStarts: [String: CanvasPoint] = [:]

    public init() {}

    public func setTables(_ newTables: [CanvasTable]) {
        setSchema(tables: newTables, edges: edges)
    }

    public func setSchema(
        tables newTables: [CanvasTable],
        edges newEdges: [CanvasEdge],
        savedPositions: [String: CanvasPoint] = [:],
        hiddenTables: Set<String> = []
    ) {
        tables = CanvasHierarchicalLayout.arrange(tables: newTables, edges: newEdges)
        if !savedPositions.isEmpty {
            for index in tables.indices {
                if let saved = savedPositions[tables[index].id] {
                    tables[index].position = saved
                }
            }
        }
        edges = newEdges
        hiddenTableIDs = hiddenTables
        selectedTableIDs = selectedTableIDs.filter { !hiddenTables.contains($0) }
        if let selected = selectedTableID, hiddenTableIDs.contains(selected) {
            selectedTableID = nil
        }
        recomputeBounds()
        pendingInitialFit = true
        CanvasDebugLog.log("setSchema: pendingInitialFit=true tables=\(tables.count)")
    }

    public func cameraWorldCenter(viewport: CGSize) -> CGPoint {
        CGPoint(
            x: (Double(viewport.width) / 2 - offset.width) / max(scale, 0.01),
            y: (Double(viewport.height) / 2 - offset.height) / max(scale, 0.01)
        )
    }

    public func recomputeBounds() {
        let laidOut = tables.filter { !hiddenTableIDs.contains($0.id) }
        guard !laidOut.isEmpty else {
            contentBounds = .zero
            return
        }
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for table in laidOut {
            minX = min(minX, table.position.x)
            minY = min(minY, table.position.y)
            maxX = max(maxX, table.position.x + CanvasCardMetrics.cardWidth)
            maxY = max(maxY, table.position.y + cardHeight(for: table))
        }
        contentBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Card Dragging

    public func beginTableDrag(id: String) {
        guard let table = table(withID: id) else { return }
        dragStarts[id] = table.position
    }

    public func updateTableDrag(id: String, translation: CGSize) {
        lastFitViewportSize = nil
        if dragStarts[id] == nil {
            dragStarts[id] = table(withID: id)?.position
        }
        guard let start = dragStarts[id] else { return }
        setPosition(
            id: id,
            x: start.x + Double(translation.width / max(scale, 0.01)),
            y: start.y + Double(translation.height / max(scale, 0.01))
        )
    }

    public func endTableDrag(id: String) {
        dragStarts.removeValue(forKey: id)
    }

    public func setPosition(id: String, x: Double, y: Double) {
        guard let index = tables.firstIndex(where: { $0.id == id }) else { return }
        tables[index].position = CanvasPoint(x: x, y: y)
        recomputeBounds()
    }

    public func table(withID id: String) -> CanvasTable? {
        tables.first { $0.id == id }
    }

    public func appendEdge(_ edge: CanvasEdge) {
        guard !edges.contains(edge) else { return }
        edges.append(edge)
    }

    public func removeEdge(id: String) {
        edges.removeAll { $0.id == id }
        if selectedEdgeID == id { selectedEdgeID = nil }
    }

    // MARK: - Selection

    public func select(table id: String) {
        selectedTableID = id
        selectedTableIDs = [id]
        selectedEdgeID = nil
    }

    public func toggleSelection(table id: String) {
        selectedEdgeID = nil
        if selectedTableIDs.contains(id) {
            selectedTableIDs.remove(id)
        } else {
            selectedTableIDs.insert(id)
        }
    }

    public func selectTables(inWorldRect rect: CGRect, extend: Bool) {
        var newSelection: Set<String> = extend ? selectedTableIDs : []
        for table in tables where !hiddenTableIDs.contains(table.id) {
            let frame = CGRect(
                x: table.position.x,
                y: table.position.y,
                width: CanvasCardMetrics.cardWidth,
                height: cardHeight(for: table)
            )
            if frame.intersects(rect) {
                newSelection.insert(table.id)
            }
        }
        selectedTableIDs = newSelection
        selectedTableID = nil
        selectedEdgeID = nil
    }

    public func dragGroup(for id: String) -> [String] {
        selectedTableIDs.contains(id) ? Array(selectedTableIDs) : [id]
    }

    public func moveFocus(from currentID: String, direction: CanvasCanvasInteractionMath.FocusDirection) {
        let heights = Dictionary(uniqueKeysWithValues: tables.map { ($0.id, cardHeight(for: $0)) })
        guard let next = CanvasCanvasInteractionMath.nextFocusID(
            from: currentID,
            direction: direction,
            tables: tables,
            heights: heights
        ) else { return }
        select(table: next)
    }

    public func select(edge id: String) {
        selectedEdgeID = id
        selectedTableID = nil
    }

    public func clearSelection() {
        selectedTableID = nil
        selectedTableIDs = []
        selectedEdgeID = nil
    }

    public var highlightedTableIDs: Set<String> {
        guard let selected = edges.first(where: { $0.id == selectedEdgeID }) else { return [] }
        return [selected.fromTableID, selected.toTableID]
    }

    // MARK: - Search & Focus

    public func matchesFilter(_ table: CanvasTable) -> Bool {
        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return table.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || table.schema?.range(of: query, options: [.caseInsensitive]) != nil
    }

    public var filteredOutTableIDs: Set<String> {
        guard !searchFilter.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Set(tables.filter { !matchesFilter($0) }.map(\.id))
    }

    public func focus(tableID: String, viewport: CGSize) {
        lastFitViewportSize = nil
        guard let table = table(withID: tableID) else { return }
        let width = CanvasCardMetrics.cardWidth * scale
        let height = CanvasCardMetrics.tableHeight(columnCount: table.columns.count) * scale
        offset = CGSize(
            width: viewport.width / 2 - (table.position.x * scale + width / 2),
            height: viewport.height / 2 - (table.position.y * scale + height / 2)
        )
        selectedTableID = tableID
        selectedEdgeID = nil
    }

    // MARK: - Narration

    public var narrationTableIDs: Set<String>? = nil

    public func beginNarrationFocus(tableIDs: [String]) {
        let ids = Set(tableIDs)
        guard !ids.isEmpty else { return }
        narrationTableIDs = ids
    }

    public func endNarrationFocus() {
        narrationTableIDs = nil
    }

    public func focusOnTables(ids: [String], viewport: CGSize) {
        lastFitViewportSize = nil
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for id in ids {
            guard !hiddenTableIDs.contains(id), let table = table(withID: id) else { continue }
            minX = min(minX, table.position.x)
            minY = min(minY, table.position.y)
            maxX = max(maxX, table.position.x + CanvasCardMetrics.cardWidth)
            maxY = max(maxY, table.position.y + cardHeight(for: table))
        }
        guard maxX.isFinite else { return }
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard bounds.width > 0, bounds.height > 0, viewport.width > 0, viewport.height > 0 else { return }
        let padding: CGFloat = 110
        let target = min(
            (viewport.width - padding * 2) / CGFloat(bounds.width),
            (viewport.height - padding * 2) / CGFloat(bounds.height)
        )
        scale = min(max(target, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        offset = CGSize(
            width: viewport.width / 2 - CGFloat(bounds.midX) * scale,
            height: viewport.height / 2 - CGFloat(bounds.midY) * scale
        )
    }

    // MARK: - Viewport

    public func pan(by delta: CGSize) {
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        lastFitViewportSize = nil
    }

    public func zoom(by factor: CGFloat) {
        scale = min(max(scale * factor, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        lastFitViewportSize = nil
    }

    public func zoomIn() { zoom(by: 1.2) }
    public func zoomOut() { zoom(by: 1 / 1.2) }

    public func fit(viewport: CGSize) {
        CanvasDebugLog.log("fit called vw=\(viewport.width) vh=\(viewport.height) bounds=\(contentBounds)")
        guard contentBounds.width > 0, contentBounds.height > 0, viewport.width > 0, viewport.height > 0 else {
            scale = 1
            offset = .zero
            lastFitViewportSize = nil
            return
        }
        let padding: CGFloat = 48
        let target = min(
            (viewport.width - padding * 2) / CGFloat(contentBounds.width),
            (viewport.height - padding * 2) / CGFloat(contentBounds.height)
        )
        scale = min(max(target, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        offset = CGSize(
            width: padding - CGFloat(contentBounds.minX) * scale,
            height: padding - CGFloat(contentBounds.minY) * scale
        )
        lastFitViewportSize = viewport
        CanvasDebugLog.log("fit done scale=\(scale) offset=\(offset)")
    }

    public func userTookCameraControl() {
        lastFitViewportSize = nil
    }

    public func center(onWorld world: CGPoint, viewport: CGSize) {
        offset = CGSize(
            width: viewport.width / 2 - world.x * scale,
            height: viewport.height / 2 - world.y * scale
        )
    }
}
