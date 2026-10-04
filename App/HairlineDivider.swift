import AppKit
import SwiftUI

extension Color {
    static let chromeSeparator: Color = Color(nsColor: NSColor(name: nil) { appearance in
        var resolved = NSColor.separatorColor
        appearance.performAsCurrentDrawingAppearance {
            let sep = NSColor.separatorColor
            let base = NSColor.windowBackgroundColor
            guard let s = sep.usingColorSpace(.sRGB), let b = base.usingColorSpace(.sRGB) else { return }
            let a = s.alphaComponent
            resolved = NSColor(
                srgbRed: s.redComponent * a + b.redComponent * (1 - a),
                green: s.greenComponent * a + b.greenComponent * (1 - a),
                blue: s.blueComponent * a + b.blueComponent * (1 - a),
                alpha: 1
            )
        }
        return resolved
    })
}

struct HairlineDivider: View {
    var orientation: Orientation = .horizontal

    enum Orientation { case horizontal, vertical }

    var body: some View {
        Rectangle()
            .fill(Color.chromeSeparator)
            .frame(
                width: orientation == .vertical ? 0.5 : nil,
                height: orientation == .horizontal ? 0.5 : nil
            )
    }
}
