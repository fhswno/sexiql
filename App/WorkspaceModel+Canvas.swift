import AppKit
import Foundation
import SwiftUI
import SQLCanvas
import SQLCore
import SQLDrivers

extension WorkspaceModel {
    func canvasViewModel(for tabID: UUID) -> CanvasViewModel {
        if let existing = canvasViewModels[tabID] { return existing }
        let viewModel = CanvasViewModel()
        canvasViewModels[tabID] = viewModel
        return viewModel
    }

    func canvasProfileID(for tabID: UUID) -> UUID? {
        document.openTabs.first(where: { $0.id == tabID })?.connectionProfileID
    }

    private func canvasLayoutKey(for profileID: UUID) -> String {
        profileID.uuidString
    }

    func loadCanvasSchema(for tabID: UUID, force: Bool = false, useSavedLayout: Bool = true) async {
        guard let viewModel = canvasViewModels[tabID] else { return }
        guard let tab = document.openTabs.first(where: { $0.id == tabID }),
              let profileID = tab.connectionProfileID,
              let profile = document.connections.first(where: { $0.id == profileID }) else {
            viewModel.isLoading = false
            viewModel.loadError = "This canvas tab is not bound to a connection."
            return
        }

        if schemaByProfile[profileID] == nil {
            await loadSchema(for: profile)
        }
        guard let snapshot = schemaByProfile[profileID] else {
            viewModel.isLoading = false
            viewModel.loadError = schemaError ?? "Schema is not loaded yet. Connect and try again."
            return
        }
        guard await connectionManager.connection(for: profileID) != nil else {
            viewModel.isLoading = false
            viewModel.loadError = "Not connected. Connect to \(profile.name) and reload the canvas."
            return
        }

        viewModel.isLoading = true
        viewModel.loadError = nil

        let tableObjects = snapshot.objects.filter { $0.kind == .table }
        var tables: [CanvasTable] = []
        var edges: [CanvasEdge] = []
        var seenEdgeIDs = Set<String>()

        for object in tableObjects {
            if force || (schemaColumnsByID[object.id] ?? []).isEmpty {
                await loadSchemaColumns(object, reportError: false, profileID: profileID)
            }
            if object.kind == .table {
                await loadSchemaRelations(object, reportError: false, profileID: profileID)
            }
            let schemaColumns = schemaColumnsByID[object.id]
                ?? schemaByProfile[profileID]?.columns[object.id]
                ?? []
            let foreignKeys = schemaForeignKeysByID[object.id] ?? []
            let foreignColumnNames = Set(foreignKeys.flatMap(\.columns))
            let canvasColumns = schemaColumns.map { column in
                CanvasColumn(
                    name: column.name,
                    dataType: column.dataType,
                    isPrimaryKey: column.isPrimaryKey,
                    isForeignKey: foreignColumnNames.contains(column.name),
                    isNullable: column.isNullable
                )
            }
            tables.append(
                CanvasTable(
                    id: object.id,
                    name: object.name,
                    schema: object.schema,
                    columns: canvasColumns,
                    position: CanvasPoint(x: 0, y: 0)
                )
            )
        }

        func resolveTable(schema: String?, name: String) -> CanvasTable? {
            tables.first { table in
                table.name.caseInsensitiveCompare(name) == .orderedSame
                    && (schema == nil
                        || table.schema?.caseInsensitiveCompare(schema!) == .orderedSame
                        || table.schema == nil)
            }
        }

        for object in tableObjects {
            let foreignKeys = schemaForeignKeysByID[object.id] ?? []
            for key in foreignKeys {
                guard let target = resolveTable(schema: key.refSchema, name: key.refTable) else { continue }
                for (index, columnName) in key.columns.enumerated() {
                    let refColumn = index < key.refColumns.count ? key.refColumns[index] : key.refColumns.first ?? ""
                    let edge = CanvasEdge(
                        fromTableID: object.id,
                        fromColumn: columnName,
                        toTableID: target.id,
                        toColumn: refColumn
                    )
                    if seenEdgeIDs.insert(edge.id).inserted {
                        edges.append(edge)
                    }
                }
            }
        }

        let virtualRelationships = document.virtualRelationships[profileID] ?? []
        for relationship in virtualRelationships {
            guard let fromTable = tables.first(where: { $0.name.caseInsensitiveCompare(relationship.fromTable) == .orderedSame }),
                  let toTable = tables.first(where: { $0.name.caseInsensitiveCompare(relationship.toTable) == .orderedSame }) else { continue }
            let edge = CanvasEdge(
                fromTableID: fromTable.id,
                fromColumn: relationship.fromColumn,
                toTableID: toTable.id,
                toColumn: relationship.toColumn,
                isVirtual: true
            )
            if seenEdgeIDs.insert(edge.id).inserted {
                edges.append(edge)
            }
        }

        let state = canvasViewState(for: profileID)
        if let rawDensity = state.density, let savedDensity = CanvasViewModel.Density(rawValue: rawDensity) {
            viewModel.setDensity(savedDensity)
        }

        if viewModel.tables.isEmpty || force {
            let saved: [String: CanvasPosition] = useSavedLayout
                ? (document.canvasLayouts[canvasLayoutKey(for: profileID)] ?? [:])
                : [:]
            let savedPositions = saved.mapValues { CanvasPoint(x: $0.x, y: $0.y) }
            viewModel.setSchema(
                tables: tables,
                edges: edges,
                savedPositions: savedPositions,
                hiddenTables: Set(state.hiddenTables)
            )
        }
        viewModel.isLoading = false
    }

    func refreshOpenCanvasTabs(for profileID: UUID) async {
        guard !isProfileBusy(profileID) else { return }
        for tab in document.openTabs where tab.kind == .canvas && tab.connectionProfileID == profileID {
            guard let viewModel = canvasViewModels[tab.id], !viewModel.tables.isEmpty else { continue }
            guard canvasNarrationModels[tab.id]?.isActive != true else { continue }
            let layoutKey = canvasLayoutKey(for: profileID)
            if (document.canvasLayouts[layoutKey] ?? [:]).isEmpty {
                var positions: [String: CanvasPosition] = [:]
                for table in viewModel.tables {
                    positions[table.id] = CanvasPosition(x: table.position.x, y: table.position.y)
                }
                document.canvasLayouts[layoutKey] = positions
                scheduleSaveWorkspace()
            }
            await loadCanvasSchema(for: tab.id, force: true)
        }
    }

    func openCanvasTable(for tabID: UUID, tableID: String) {
        guard let profileID = canvasProfileID(for: tabID),
              let snapshot = schemaByProfile[profileID],
              let object = snapshot.objects.first(where: { $0.id == tableID }) else { return }
        selectedConnectionID = profileID
        openSchemaObject(object)
    }

    func addVirtualRelationship(
        for tabID: UUID,
        fromTableID: String,
        fromColumn: String,
        toTableID: String,
        toColumn: String
    ) {
        guard let viewModel = canvasViewModels[tabID],
              let profileID = canvasProfileID(for: tabID),
              let fromTable = viewModel.table(withID: fromTableID),
              let toTable = viewModel.table(withID: toTableID) else { return }
        guard fromTableID != toTableID || fromColumn != toColumn else { return }

        var relationships = document.virtualRelationships[profileID] ?? []
        let relationship = VirtualRelationship(
            fromTable: fromTable.name,
            fromColumn: fromColumn,
            toTable: toTable.name,
            toColumn: toColumn
        )
        guard !relationships.contains(relationship) else { return }
        relationships.append(relationship)
        document.virtualRelationships[profileID] = relationships
        saveWorkspace()

        viewModel.appendEdge(
            CanvasEdge(
                fromTableID: fromTableID,
                fromColumn: fromColumn,
                toTableID: toTableID,
                toColumn: toColumn,
                isVirtual: true
            )
        )
    }

    func deleteVirtualRelationship(for tabID: UUID, edge: CanvasEdge) {
        guard edge.isVirtual,
              let viewModel = canvasViewModels[tabID],
              let profileID = canvasProfileID(for: tabID),
              let fromTable = viewModel.table(withID: edge.fromTableID),
              let toTable = viewModel.table(withID: edge.toTableID) else { return }

        document.virtualRelationships[profileID]?.removeAll { relationship in
            relationship.fromTable.caseInsensitiveCompare(fromTable.name) == .orderedSame
                && relationship.fromColumn.caseInsensitiveCompare(edge.fromColumn) == .orderedSame
                && relationship.toTable.caseInsensitiveCompare(toTable.name) == .orderedSame
                && relationship.toColumn.caseInsensitiveCompare(edge.toColumn) == .orderedSame
        }
        saveWorkspace()
        viewModel.removeEdge(id: edge.id)
    }

    func canvasViewState(for profileID: UUID) -> CanvasViewState {
        document.canvasViewStates[profileID.uuidString] ?? CanvasViewState()
    }

    func canvasNarrationModel(for tabID: UUID) -> CanvasNarrationModel {
        if let existing = canvasNarrationModels[tabID] { return existing }
        let model = CanvasNarrationModel()
        canvasNarrationModels[tabID] = model
        return model
    }

    func beginCanvasNarration(for tabID: UUID) async {
        guard let viewModel = canvasViewModels[tabID], !viewModel.visibleTables.isEmpty else { return }
        guard await ensureAIReady(for: tabID, pending: nil) else { return }
        guard canvasProfileID(for: tabID) != nil else { return }

        let summary = CanvasGraphSummary.build(tables: viewModel.tables, edges: viewModel.edges)
        let selectedTableIDs = Array(viewModel.selectedTableIDs)
        let narrationModel = canvasNarrationModel(for: tabID)
        viewModel.clearSelection()
        narrationModel.begin(
            knownTableIDs: Set(viewModel.tables.map(\.id)),
            knownEdgeIDs: Set(viewModel.edges.map(\.id)),
            system: CanvasNarrationPrompt.systemPrompt,
            user: CanvasNarrationPrompt.userPrompt(summary: summary, selectedTableIDs: selectedTableIDs),
            modelName: ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURLString: ollamaBaseURL
        )
    }

    func cancelCanvasNarration(for tabID: UUID) {
        canvasNarrationModels[tabID]?.cancel()
        if let viewModel = canvasViewModels[tabID] {
            viewModel.endNarrationFocus()
        }
    }

    func applyNarrationSegment(for tabID: UUID) {
        guard let narrationModel = canvasNarrationModels[tabID],
              let viewModel = canvasViewModels[tabID],
              let segment = narrationModel.currentSegment else {
            if canvasViewModels[tabID] != nil {
                canvasViewModels[tabID]?.endNarrationFocus()
            }
            return
        }
        var ids = segment.tableIDs
        for edgeID in segment.edgeIDs {
            if let edge = viewModel.edges.first(where: { $0.id == edgeID }) {
                ids.append(edge.fromTableID)
                ids.append(edge.toTableID)
            }
        }
        viewModel.beginNarrationFocus(tableIDs: ids)
    }


    func persistCanvasViewState(for tabID: UUID) {
        guard let viewModel = canvasViewModels[tabID],
              let profileID = canvasProfileID(for: tabID) else { return }
        var state = canvasViewState(for: profileID)
        state.density = viewModel.density.rawValue
        state.hiddenTables = Array(viewModel.hiddenTableIDs)
        document.canvasViewStates[profileID.uuidString] = state
        scheduleSaveWorkspace()
    }

    func exportCanvasPNG(for tabID: UUID) {
        guard let viewModel = canvasViewModels[tabID], !viewModel.tables.isEmpty else {
            activeError = "Nothing to export yet — the canvas is empty."
            return
        }
        let bounds = viewModel.contentBounds
        let scale: CGFloat = 2
        let exportView = CanvasStaticView(
            tables: viewModel.tables,
            edges: viewModel.edges,
            scale: scale,
            contentBounds: bounds
        )
        let hosting = NSHostingView(rootView: exportView)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            activeError = "Could not render the canvas for export."
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            activeError = "Could not encode the canvas as PNG."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "SexiQL-canvas.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
            } catch {
                Task { @MainActor in
                    self.activeError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func persistCanvasLayout(for tabID: UUID) {
        guard let viewModel = canvasViewModels[tabID],
              let profileID = canvasProfileID(for: tabID), !viewModel.tables.isEmpty else { return }
        var layout: [String: CanvasPosition] = [:]
        for table in viewModel.tables {
            layout[table.id] = CanvasPosition(x: table.position.x, y: table.position.y)
        }
        document.canvasLayouts[canvasLayoutKey(for: profileID)] = layout
        scheduleSaveWorkspace()
    }

    func resetCanvasLayout(for tabID: UUID) {
        guard let profileID = canvasProfileID(for: tabID) else { return }
        document.canvasLayouts[canvasLayoutKey(for: profileID)] = nil
        var state = canvasViewState(for: profileID)
        state.cameraX = nil
        state.cameraY = nil
        state.cameraScale = nil
        document.canvasViewStates[profileID.uuidString] = state
        saveWorkspace()
        Task { await loadCanvasSchema(for: tabID, force: true, useSavedLayout: false) }
    }
}
