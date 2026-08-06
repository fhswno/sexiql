import AppKit
import SQLCore


@MainActor
enum AppIconAppearance {
    static func apply(for mode: AppearanceMode) {
        let useLight: Bool
        switch mode {
        case .light:
            useLight = true
        case .dark:
            useLight = false
        case .system:
            useLight = isSystemAppearanceLight()
        }
        apply(light: useLight)
    }

    static func apply(light: Bool) {
        let name = light ? "AppIcon-light" : "AppIcon-dark"
        if let image = loadPNG(named: name) {
            NSApp.applicationIconImage = image
            return
        }
        if light, let image = loadPNG(named: "AppIcon-light") ?? loadPNG(named: "AppIcon") {
            NSApp.applicationIconImage = image
        } else if let image = loadPNG(named: "AppIcon-dark") ?? loadPNG(named: "AppIcon") {
            NSApp.applicationIconImage = image
        }
    }

    static func isSystemAppearanceLight() -> Bool {
        let appearance = NSApp.effectiveAppearance
        let matched = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        return matched == .aqua || matched == .vibrantLight
    }

    private static func loadPNG(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
}
