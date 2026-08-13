import SwiftUI

public enum SexiQLColors {
    public static let connected = Color.green
    public static let connecting = Color.orange
    public static let failed = Color.red
    public static let disconnected = Color.secondary

    public static let selectionFill = Color.accentColor.opacity(0.14)
    public static let selectionFillStrong = Color.accentColor.opacity(0.22)
    public static let hoverFill = Color.primary.opacity(0.05)
    public static let hairline = Color.primary.opacity(0.08)
    public static let glassStroke = Color.white.opacity(0.08)

    public static func chromeTint(_ name: String?, scheme: ColorScheme) -> Color {
        switch name {
        case "blue", "indigo": .blue
        case "orange": .orange
        case "green", "teal": .green
        case "purple", "pink": .purple
        default:
            scheme == .dark ? .white : Color(white: 0.22)
        }
    }

    public static func engine(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "postgres", "postgresql": return Color(red: 0.33, green: 0.47, blue: 0.75)
        case "mysql": return Color(red: 0.90, green: 0.55, blue: 0.20)
        case "sqlite": return Color(red: 0.35, green: 0.62, blue: 0.85)
        default: return .accentColor
        }
    }

    public static func status(_ name: String) -> Color {
        switch name {
        case "connected": connected
        case "connecting", "running", "streaming", "pending": connecting
        case "failed": failed
        default: disconnected
        }
    }
}
