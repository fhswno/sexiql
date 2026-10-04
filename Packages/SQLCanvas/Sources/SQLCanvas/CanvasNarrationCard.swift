import SwiftUI

public struct CanvasNarrationCard: View {
    public let segments: [NarrationSegment]
    @Binding public var currentIndex: Int
    public let isStreaming: Bool
    public let streamingTail: String
    public var tableName: (String) -> String = { $0 }
    public var onSelectTable: (String) -> Void = { _ in }
    public var onClose: () -> Void = {}
    public var onStep: (Int) -> Void = { _ in }

    @State private var showAll = false
    @State private var hoveredStep: Int?

    public init(
        segments: [NarrationSegment],
        currentIndex: Binding<Int>,
        isStreaming: Bool,
        streamingTail: String,
        tableName: @escaping (String) -> String = { $0 },
        onSelectTable: @escaping (String) -> Void = { _ in },
        onClose: @escaping () -> Void = {},
        onStep: @escaping (Int) -> Void = { _ in }
    ) {
        self.segments = segments
        _currentIndex = currentIndex
        self.isStreaming = isStreaming
        self.streamingTail = streamingTail
        self.tableName = tableName
        self.onSelectTable = onSelectTable
        self.onClose = onClose
        self.onStep = onStep
    }

    private var safeIndex: Int? {
        segments.indices.contains(currentIndex) ? currentIndex : nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if showAll {
                outline
            } else {
                currentSegmentBody
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Schema Story")
                .font(.system(size: 11, weight: .semibold))
            if isStreaming {
                ProgressView()
                    .controlSize(.mini)
            }
            Spacer()
            if !segments.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showAll.toggle() }
                } label: {
                    Text(showAll ? "Steps" : "View all")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .pointerStyle(.link)
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .pointerStyle(.link)
            .help("Exit story (Esc)")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    @ViewBuilder
    private var currentSegmentBody: some View {
        if segments.isEmpty {
            streamingBody
        } else if let segment = safeIndex.map({ segments[$0] }) {
            VStack(alignment: .leading, spacing: 8) {
                if !segment.title.isEmpty {
                    Text(segment.title)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(segment.text)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !segment.tableIDs.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(segment.tableIDs, id: \.self) { tableID in
                            Button {
                                onSelectTable(tableID)
                            } label: {
                                Text(tableName(tableID))
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .pointerStyle(.link)
                            .help("Focus this table")
                        }
                    }
                }
                footer
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var streamingBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading the schema…")
                .font(.system(size: 12, weight: .medium))
            Text(String(streamingTail.suffix(160)))
                .font(.system(size: 10).monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(segments.indices, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: 6, height: 6)
                    .onTapGesture { onStep(index) }
                    .pointerStyle(.link)
            }
            Spacer()
            Button {
                onStep(max(currentIndex - 1, 0))
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .pointerStyle(.link)
            .disabled(currentIndex == 0)
            Text("Step \(min(currentIndex + 1, max(segments.count, 1))) of \(max(segments.count, 1))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                onStep(min(currentIndex + 1, segments.count - 1))
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .pointerStyle(.link)
            .disabled(currentIndex >= segments.count - 1)
        }
    }

    private var outline: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(segments.indices, id: \.self) { index in
                        let segment = segments[index]
                        Button {
                            onStep(index)
                            withAnimation(.easeOut(duration: 0.18)) { showAll = false }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(index == currentIndex ? Color.accentColor : Color.primary.opacity(0.2))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 1) {
                                    if !segment.title.isEmpty {
                                        Text(segment.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(index == currentIndex ? Color.primary : Color.secondary)
                                    }
                                    Text(segment.text)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(hoveredStep == index ? Color.primary.opacity(0.06) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .onHover { hovering in
                            hoveredStep = hovering ? index : (hoveredStep == index ? nil : hoveredStep)
                        }
                    }
                    if isStreaming {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Writing…")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 220)
            .onScrollPhaseChange { _, phase in
                if phase != .idle {
                    hoveredStep = nil
                }
            }
            .onChange(of: showAll) { _, _ in
                hoveredStep = nil
            }
        }
    }
}
