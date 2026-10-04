import SwiftUI

public struct CanvasTableListPanel: View {
    @Binding public var filter: String
    public let tables: [CanvasTable]
    public let hiddenTables: [String]
    public let onShow: (String) -> Void
    public let onShowAll: () -> Void
    public let onSelect: (String) -> Void
    @State private var collapsed = true
    @FocusState private var searchFocused: Bool

    public init(
        filter: Binding<String>,
        tables: [CanvasTable],
        hiddenTables: [String] = [],
        onShow: @escaping (String) -> Void = { _ in },
        onShowAll: @escaping () -> Void = {},
        onSelect: @escaping (String) -> Void
    ) {
        _filter = filter
        self.tables = tables
        self.hiddenTables = hiddenTables
        self.onShow = onShow
        self.onShowAll = onShowAll
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.borderless)
                .pointerStyle(.link)
                .help(collapsed ? "Show tables" : "Hide tables")
                Text("Tables")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(tables.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { collapsed.toggle() } }

            if !collapsed {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    TextField("Filter tables", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused($searchFocused)
                    if !filter.isEmpty {
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .pointerStyle(.link)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))

                if tables.isEmpty {
                    Text("No tables")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(tables) { table in
                                row(table)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 240)
                }

                if !hiddenTables.isEmpty {
                    Divider()
                    HStack {
                        Text("Hidden")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore all") {
                            onShowAll()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 5)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: 5)],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(hiddenTables, id: \.self) { name in
                            HStack(spacing: 4) {
                                Text(name)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                Button {
                                    onShow(name)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .pointerStyle(.link)
                                .help("Show table")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .contentShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 208)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(_ table: CanvasTable) -> some View {
        Button {
            onSelect(table.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tablecells")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(table.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer()
                Text("\(table.columns.count)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}
