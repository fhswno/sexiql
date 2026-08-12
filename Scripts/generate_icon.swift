import AppKit
import Foundation

let S: CGFloat = 1024
let cornerR: CGFloat = S * 0.223

struct IconTheme {
    let isLight: Bool
    let fieldTop: NSColor
    let fieldBot: NSColor
    let dropHi: NSColor
    let dropMid: NSColor
    let dropLo: NSColor

    static let dark = IconTheme(
        isLight: false,
        fieldTop: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1),
        fieldBot: NSColor(calibratedRed: 0.05, green: 0.055, blue: 0.07, alpha: 1),
        dropHi: NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.90, alpha: 1),
        dropMid: NSColor(calibratedRed: 0.93, green: 0.84, blue: 0.68, alpha: 1),
        dropLo: NSColor(calibratedRed: 0.62, green: 0.50, blue: 0.32, alpha: 1)
    )

    static let light = IconTheme(
        isLight: true,
        fieldTop: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        fieldBot: NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.93, alpha: 1),
        dropHi: NSColor(calibratedRed: 0.72, green: 0.86, blue: 1.00, alpha: 1),
        dropMid: NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.92, alpha: 1),
        dropLo: NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.58, alpha: 1)
    )
}

func oval(_ r: NSRect) -> NSBezierPath { NSBezierPath(ovalIn: r) }
func rr(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
}
func fill(_ path: NSBezierPath, _ color: NSColor) { color.setFill(); path.fill() }
func stroke(_ path: NSBezierPath, _ color: NSColor, _ w: CGFloat) {
    color.setStroke(); path.lineWidth = w; path.stroke()
}
func radial(center: NSPoint, radius: CGFloat, colors: [NSColor]) {
    let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    NSGradient(colors: colors)?.draw(in: oval(rect), relativeCenterPosition: .zero)
}

func droplet(in bounds: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    let cx = bounds.midX
    let top = NSPoint(x: cx, y: bounds.maxY)
    let left = NSPoint(x: bounds.minX, y: bounds.minY + bounds.height * 0.38)
    let right = NSPoint(x: bounds.maxX, y: bounds.minY + bounds.height * 0.38)
    let bottom = NSPoint(x: cx, y: bounds.minY)
    path.move(to: top)
    path.curve(
        to: left,
        controlPoint1: NSPoint(x: cx - bounds.width * 0.06, y: bounds.maxY - bounds.height * 0.12),
        controlPoint2: NSPoint(x: bounds.minX, y: bounds.maxY - bounds.height * 0.32)
    )
    path.curve(
        to: bottom,
        controlPoint1: NSPoint(x: bounds.minX, y: bounds.minY + bounds.height * 0.16),
        controlPoint2: NSPoint(x: cx - bounds.width * 0.46, y: bounds.minY)
    )
    path.curve(
        to: right,
        controlPoint1: NSPoint(x: cx + bounds.width * 0.46, y: bounds.minY),
        controlPoint2: NSPoint(x: bounds.maxX, y: bounds.minY + bounds.height * 0.16)
    )
    path.curve(
        to: top,
        controlPoint1: NSPoint(x: bounds.maxX, y: bounds.maxY - bounds.height * 0.32),
        controlPoint2: NSPoint(x: cx + bounds.width * 0.06, y: bounds.maxY - bounds.height * 0.12)
    )
    path.close()
    return path
}

func renderIcon(theme t: IconTheme) -> NSImage {
    NSImage(size: NSSize(width: S, height: S), flipped: false) { full in
        NSColor.clear.setFill()
        full.fill(using: .copy)

        let margin = S * 0.08
        let rect = full.insetBy(dx: margin, dy: margin)
        let corner = cornerR * (rect.width / S)
        let tile = rr(rect, corner)

        NSGradient(colorsAndLocations:
            (t.fieldTop, 0.0),
            (t.fieldBot, 1.0)
        )?.draw(in: tile, angle: -86)

        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        radial(
            center: NSPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.84),
            radius: rect.width * 0.58,
            colors: [
                NSColor.white.withAlphaComponent(t.isLight ? 0.55 : 0.14),
                NSColor.white.withAlphaComponent(0.0),
            ]
        )
        radial(
            center: NSPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.16),
            radius: rect.width * 0.48,
            colors: [
                NSColor.black.withAlphaComponent(t.isLight ? 0.06 : 0.45),
                NSColor.black.withAlphaComponent(0.0),
            ]
        )
        NSGraphicsContext.restoreGraphicsState()

        let dropW = rect.width * 0.38
        let dropH = rect.height * 0.50
        let dropRect = NSRect(
            x: rect.midX - dropW * 0.50,
            y: rect.midY - dropH * 0.46,
            width: dropW,
            height: dropH
        )
        let drop = droplet(in: dropRect)

        for i in (1...6).reversed() {
            let f = CGFloat(i) / 6
            let shadow = drop.copy() as! NSBezierPath
            shadow.transform(using: AffineTransform(translationByX: 0, byY: -rect.height * 0.018 * f))
            NSColor.black.withAlphaComponent((t.isLight ? 0.06 : 0.16) * f).setFill()
            shadow.fill()
        }

        NSGradient(colorsAndLocations:
            (t.dropHi, 0.0),
            (t.dropMid, 0.42),
            (t.dropLo, 1.0)
        )?.draw(in: drop, angle: -78)

        NSGraphicsContext.saveGraphicsState()
        drop.addClip()
        radial(
            center: NSPoint(x: dropRect.midX - dropW * 0.12, y: dropRect.minY + dropH * 0.68),
            radius: dropW * 0.55,
            colors: [
                NSColor.white.withAlphaComponent(t.isLight ? 0.55 : 0.42),
                t.dropHi.withAlphaComponent(0.20),
                NSColor.white.withAlphaComponent(0.0),
            ]
        )
        radial(
            center: NSPoint(x: dropRect.midX + dropW * 0.18, y: dropRect.minY + dropH * 0.18),
            radius: dropW * 0.42,
            colors: [
                t.dropLo.blended(withFraction: 0.35, of: .black)!.withAlphaComponent(0.55),
                t.dropLo.withAlphaComponent(0.0),
            ]
        )
        NSGraphicsContext.restoreGraphicsState()

        stroke(drop, NSColor.white.withAlphaComponent(t.isLight ? 0.55 : 0.28), S * 0.006)

        let spec = oval(NSRect(
            x: dropRect.midX - dropW * 0.22,
            y: dropRect.minY + dropH * 0.58,
            width: dropW * 0.34,
            height: dropH * 0.16
        ))
        fill(spec, NSColor.white.withAlphaComponent(t.isLight ? 0.70 : 0.50))

        stroke(tile, NSColor.white.withAlphaComponent(t.isLight ? 0.80 : 0.16), S * 0.005)
        let inner = rr(rect.insetBy(dx: S * 0.006, dy: S * 0.006), corner * 0.96)
        stroke(inner, NSColor.black.withAlphaComponent(t.isLight ? 0.08 : 0.40), S * 0.003)

        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(t.isLight ? 0.45 : 0.18),
            NSColor.white.withAlphaComponent(0.0),
        ])?.draw(
            in: NSRect(x: rect.minX, y: rect.minY + rect.height * 0.70, width: rect.width, height: rect.height * 0.30),
            angle: -90
        )
        NSGraphicsContext.restoreGraphicsState()

        return true
    }
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SexiQLIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "encode failed"])
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: url, options: .atomic)
}

let base = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")

do {
    try writePNG(renderIcon(theme: .dark), to: base.appendingPathComponent("AppIcon.png"))
    try writePNG(renderIcon(theme: .light), to: base.appendingPathComponent("AppIcon-light.png"))
    print("Wrote dark + light icons")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
