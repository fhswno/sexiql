import SwiftUI
import SQLCanvas

struct CanvasVirtualSheetItem: Identifiable {
    let id = UUID()
    let tableID: String
    let column: String
}

struct SchemaCanvasContainerView: View {
    @Environment(WorkspaceModel.self) private var model
    let tabID: UUID
    @State private var virtualSheet: CanvasVirtualSheetItem?

    var body: some View {
        let viewModel = model.canvasViewModel(for: tabID)
        let narrationModel = model.canvasNarrationModel(for: tabID)
        let profileID = model.canvasProfileID(for: tabID)
        let isConnected = profileID.map { model.status(for: $0) == .connected } ?? false
        SchemaCanvasView(
            viewModel: viewModel,
            edgeNotation: model.document.settings.edgeNotation == .crowFoot ? .crowFoot : .labels,
            onCardDragEnd: {
                model.persistCanvasLayout(for: tabID)
            },
            onOpenTable: { tableID in
                model.openCanvasTable(for: tabID, tableID: tableID)
            },
            onAddVirtualRelationship: { pair in
                virtualSheet = CanvasVirtualSheetItem(tableID: pair.tableID, column: pair.column)
            },
            onDeleteVirtualRelationship: { edge in
                model.deleteVirtualRelationship(for: tabID, edge: edge)
            },
            onStateChanged: {
                model.persistCanvasViewState(for: tabID)
            },
            isNarrationActive: {
                narrationModel.isActive
            },
            onNarrationStep: { delta in
                narrationModel.step(delta)
            },
            onNarrationExit: {
                model.cancelCanvasNarration(for: tabID)
            },
            scrollCaptureEnabled: !narrationModel.isActive
        )
        .overlay(alignment: .topTrailing) {
            if model.aiEnabled, !narrationModel.isActive, !viewModel.visibleTables.isEmpty {
                Button {
                    Task { await model.beginCanvasNarration(for: tabID) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.primary)
                        Text(viewModel.selectedTableIDs.isEmpty ? "Explain Schema" : "Explain Selection")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .pointerStyle(.link)
                .help("Guided tour of this schema, powered by your local AI")
                .padding(.top, 10)
                .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .bottom) {
            if narrationModel.isActive {
                CanvasNarrationCard(
                    segments: narrationModel.segments,
                    currentIndex: Binding(
                        get: { narrationModel.currentIndex },
                        set: { narrationModel.jump(to: $0) }
                    ),
                    isStreaming: narrationModel.isStreaming,
                    streamingTail: narrationModel.streamingTail,
                    tableName: { tableID in
                        viewModel.table(withID: tableID)?.name ?? tableID
                    },
                    onSelectTable: { tableID in
                        viewModel.select(table: tableID)
                    },
                    onClose: {
                        model.cancelCanvasNarration(for: tabID)
                    },
                    onStep: { index in
                        narrationModel.jump(to: index)
                    }
                )
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: narrationModel.currentIndex) { _, _ in
            withAnimation(.easeInOut(duration: 0.45)) {
                model.applyNarrationSegment(for: tabID)
            }
        }
        .onChange(of: narrationModel.segments.count) { _, _ in
            model.applyNarrationSegment(for: tabID)
        }
        .onChange(of: narrationModel.isActive) { _, active in
            if !active {
                viewModel.endNarrationFocus()
            }
        }
        .sheet(item: Binding(
            get: { virtualSheet },
            set: { virtualSheet = $0 }
        )) { item in
            VirtualRelationshipSheet(
                sourceTableName: viewModel.table(withID: item.tableID)?.name ?? item.tableID,
                sourceColumnName: item.column,
                tables: viewModel.tables,
                onCancel: { virtualSheet = nil },
                onSave: { targetTableID, targetColumn in
                    model.addVirtualRelationship(
                        for: tabID,
                        fromTableID: item.tableID,
                        fromColumn: item.column,
                        toTableID: targetTableID,
                        toColumn: targetColumn
                    )
                    virtualSheet = nil
                }
            )
        }
        .task(id: tabID) {
            if viewModel.tables.isEmpty, viewModel.loadError == nil, !viewModel.isLoading {
                await model.loadCanvasSchema(for: tabID)
            }
        }
        .onChange(of: isConnected) { _, connected in
            if connected, viewModel.tables.isEmpty {
                Task { await model.loadCanvasSchema(for: tabID) }
            }
        }
        .onChange(of: viewModel.offset) { _, _ in
            model.persistCanvasViewState(for: tabID)
        }
        .onChange(of: viewModel.scale) { _, _ in
            model.persistCanvasViewState(for: tabID)
        }
        .contextMenu {
            Button("Reload Schema") {
                Task { await model.loadCanvasSchema(for: tabID, force: true) }
            }
            Button("Reset Layout") {
                model.resetCanvasLayout(for: tabID)
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading, !viewModel.tables.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading schema…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .padding(.top, 10)
            }
        }
    }
}
