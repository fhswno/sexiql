import SwiftUI

public struct Glass: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color?

    public init(cornerRadius: CGFloat = SexiQLRadius.xl, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.08))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(SexiQLColors.glassStroke, lineWidth: 0.5)
            }
    }
}

public extension View {
    func glass(cornerRadius: CGFloat = SexiQLRadius.xl, tint: Color? = nil) -> some View {
        modifier(Glass(cornerRadius: cornerRadius, tint: tint))
    }
}

public struct EmptyStateView: View {
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(
        title: String,
        subtitle: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: SexiQLSpace.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(SexiQLType.emptyTitle)
            Text(subtitle)
                .font(SexiQLType.emptyBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, SexiQLSpace.xs)
            }
        }
        .padding(SexiQLSpace.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct StatusDot: View {
    public var color: Color
    public var size: CGFloat

    public init(color: Color, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

public struct EngineBadge: View {
    public var systemImage: String
    public var color: Color

    public init(systemImage: String, color: Color) {
        self.systemImage = systemImage
        self.color = color
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
    }
}
