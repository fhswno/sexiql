import SwiftUI

public struct ChromeSectionHeader<Trailing: View>: View {
    public var title: String
    @ViewBuilder public var trailing: () -> Trailing

    public init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: SexiQLSpace.sm) {
            Text(title)
                .font(SexiQLType.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: 22, alignment: .center)
        .padding(.horizontal, SexiQLSpace.lg)
        .padding(.top, SexiQLSpace.xl)
        .padding(.bottom, SexiQLSpace.sm)
    }
}

public extension ChromeSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

public struct SidebarModePicker<Mode: Hashable>: View {
    public var modes: [(Mode, String, String)]
    @Binding public var selection: Mode

    public init(modes: [(Mode, String, String)], selection: Binding<Mode>) {
        self.modes = modes
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: SexiQLSpace.xxs) {
            ForEach(modes, id: \.0) { mode, title, systemImage in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .background {
                            if selection == mode {
                                RoundedRectangle(cornerRadius: SexiQLRadius.sm, style: .continuous)
                                    .fill(SexiQLColors.selectionFillStrong)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(title)
                .foregroundStyle(selection == mode ? Color.accentColor : Color.secondary)
            }
        }
        .padding(SexiQLSpace.xs)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .padding(.horizontal, SexiQLSpace.md)
        .frame(maxWidth: .infinity, minHeight: SexiQLLayout.secondaryChromeHeight, maxHeight: SexiQLLayout.secondaryChromeHeight)
        .background(.bar)
    }
}

public struct SelectableRow: View {
    public var title: String
    public var subtitle: String
    public var systemImage: String?
    public var imageColor: Color
    public var isSelected: Bool
    public var action: () -> Void

    public init(
        title: String,
        subtitle: String = "",
        systemImage: String? = nil,
        imageColor: Color = .secondary,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.imageColor = imageColor
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: SexiQLSpace.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(isSelected ? Color.accentColor : imageColor)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SexiQLType.rowTitle.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(SexiQLType.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, SexiQLSpace.sm)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: SexiQLRadius.md, style: .continuous)
                    .fill(SexiQLColors.selectionFill)
            }
        }
    }
}

public struct ConnectionRowView: View {
    public var name: String
    public var subtitle: String
    public var systemImage: String
    public var isSelected: Bool
    public var action: () -> Void

    public init(name: String, subtitle: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
        self.name = name
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        SelectableRow(
            title: name,
            subtitle: subtitle,
            systemImage: systemImage,
            imageColor: isSelected ? .accentColor : .secondary,
            isSelected: isSelected,
            action: action
        )
    }
}

public struct KeyValueRow: View {
    public var label: String
    public var value: String
    public var labelWidth: CGFloat

    public init(label: String, value: String, labelWidth: CGFloat = 72) {
        self.label = label
        self.value = value
        self.labelWidth = labelWidth
    }

    public var body: some View {
        HStack(alignment: .top, spacing: SexiQLSpace.md) {
            Text(label)
                .font(SexiQLType.rowSubtitle)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(SexiQLType.rowTitle)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
    }
}
