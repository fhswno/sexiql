import AppKit
import Foundation

let S: CGFloat = 1024
let cornerR: CGFloat = S * 0.223

// MARK: - Theme

struct IconTheme {
    let void, plum, royal, electric, topViolet: NSColor
    let ice, iceTint: NSColor
    let rose, coral, blush, magenta: NSColor
    let plateFrost, plateWash: CGFloat
    let idleCellTop, idleCellBot: CGFloat
    let isLight: Bool

    static let dark = IconTheme(
        void: NSColor(calibratedRed: 0.07, green: 0.03, blue: 0.14, alpha: 1),
        plum: NSColor(calibratedRed: 0.16, green: 0.06, blue: 0.28, alpha: 1),
        royal: NSColor(calibratedRed: 0.32, green: 0.14, blue: 0.55, alpha: 1),
        electric: NSColor(calibratedRed: 0.48, green: 0.28, blue: 0.82, alpha: 1),
        topViolet: NSColor(calibratedRed: 0.58, green: 0.40, blue: 0.92, alpha: 1),
        ice: NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.98, alpha: 1),
        iceTint: NSColor(calibratedRed: 0.88, green: 0.86, blue: 0.96, alpha: 1),
        rose: NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.62, alpha: 1),
        coral: NSColor(calibratedRed: 1.00, green: 0.52, blue: 0.68, alpha: 1),
        blush: NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.84, alpha: 1),
        magenta: NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.72, alpha: 1),
        plateFrost: 0.07, plateWash: 0.06,
        idleCellTop: 0.42, idleCellBot: 0.16,
        isLight: false
    )

    static let light = IconTheme(
        void: NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.93, alpha: 1),
        plum: NSColor(calibratedRed: 0.93, green: 0.92, blue: 0.96, alpha: 1),
        royal: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.98, alpha: 1),
        electric: NSColor(calibratedRed: 0.98, green: 0.97, blue: 1.00, alpha: 1),
        topViolet: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        ice: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        iceTint: NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.97, alpha: 1),
        rose: NSColor(calibratedRed: 0.92, green: 0.18, blue: 0.48, alpha: 1),
        coral: NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.62, alpha: 1),
        blush: NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.88, alpha: 1),
        magenta: NSColor(calibratedRed: 0.82, green: 0.12, blue: 0.52, alpha: 1),
        plateFrost: 0.55, plateWash: 0.12,
        idleCellTop: 0.88, idleCellBot: 0.22,
        isLight: true
    )
}

// MARK: - Primitives

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
func sparkPath(center: NSPoint, outer: CGFloat, innerRatio: CGFloat = 0.34) -> NSBezierPath {
    let path = NSBezierPath()
    let inner = outer * innerRatio
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 - .pi / 2
        let r = i.isMultiple(of: 2) ? outer : inner
        let p = NSPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close()
    return path
}
func softShadow(under path: NSBezierPath, dy: CGFloat, steps: Int = 5, alpha: CGFloat = 0.055) {
    for i in (1...steps).reversed() {
        let t = CGFloat(i) / CGFloat(steps)
        let copy = path.copy() as! NSBezierPath
        copy.transform(using: AffineTransform(translationByX: 0, byY: dy * t))
        NSColor.black.withAlphaComponent(alpha * t).setFill()
        copy.fill()
    }
}

// MARK: - Render New Appearance

func renderIcon(theme t: IconTheme) -> NSImage {
    NSImage(size: NSSize(width: S, height: S), flipped: false) { fullRect in
        let margin = S * 0.08
        let rect = fullRect.insetBy(dx: margin, dy: margin)
        let corner = cornerR * (rect.width / S)
        let outer = rr(rect, corner)

        NSColor.clear.setFill()
        fullRect.fill(using: .copy)

        if t.isLight {
            NSGradient(colorsAndLocations:
                (NSColor.white, 0.0),
                (t.electric, 0.35),
                (t.plum, 0.75),
                (t.void, 1.0)
            )?.draw(in: outer, angle: -70)
            NSGraphicsContext.saveGraphicsState()
            outer.addClip()
            radial(center: NSPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.72), radius: rect.width * 0.38, colors: [
                t.blush.withAlphaComponent(0.22),
                t.rose.withAlphaComponent(0.06),
                t.rose.withAlphaComponent(0.0),
            ])
            radial(center: NSPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.18), radius: rect.width * 0.5, colors: [
                NSColor(calibratedRed: 0.55, green: 0.52, blue: 0.62, alpha: 0.22),
                NSColor(calibratedRed: 0.55, green: 0.52, blue: 0.62, alpha: 0.0),
            ])
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGradient(colorsAndLocations:
                (t.topViolet, 0.0),
                (t.electric, 0.22),
                (t.royal, 0.48),
                (t.plum, 0.78),
                (t.void, 1.0)
            )?.draw(in: outer, angle: -58)
            NSGraphicsContext.saveGraphicsState()
            outer.addClip()
            radial(center: NSPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.78), radius: rect.width * 0.48, colors: [
                t.rose.withAlphaComponent(0.50),
                t.magenta.withAlphaComponent(0.18),
                t.rose.withAlphaComponent(0.0),
            ])
            radial(center: NSPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.16), radius: rect.width * 0.55, colors: [
                t.void.withAlphaComponent(0.75),
                t.void.withAlphaComponent(0.0),
            ])
            radial(center: NSPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.88), radius: rect.width * 0.35, colors: [
                t.topViolet.withAlphaComponent(0.55),
                t.topViolet.withAlphaComponent(0.0),
            ])
            NSGraphicsContext.restoreGraphicsState()
        }

        softShadow(under: outer, dy: -rect.height * 0.02, steps: 6, alpha: t.isLight ? 0.05 : 0.07)

        let plateInset = rect.width * 0.082
        let plateRect = rect.insetBy(dx: plateInset, dy: plateInset)
        let plate = rr(plateRect, corner * 0.70)
        softShadow(under: plate, dy: -rect.height * 0.028, steps: 8, alpha: t.isLight ? 0.06 : 0.055)

        if t.isLight {
            fill(plate, NSColor.white.withAlphaComponent(0.72))
            fill(plate, t.ice.withAlphaComponent(0.15))
            stroke(plate, NSColor.white.withAlphaComponent(0.95), S * 0.004)
            stroke(plate, NSColor(calibratedWhite: 0.55, alpha: 0.18), S * 0.0025)
        } else {
            fill(plate, NSColor.white.withAlphaComponent(t.plateFrost))
            fill(plate, t.ice.withAlphaComponent(t.plateWash))
            fill(plate, t.royal.withAlphaComponent(0.10))
            stroke(plate, NSColor.white.withAlphaComponent(0.22), S * 0.003)
        }

        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        let plateSpec = NSRect(
            x: plateRect.minX + plateRect.width * 0.05,
            y: plateRect.midY + plateRect.height * 0.08,
            width: plateRect.width * 0.90,
            height: plateRect.height * 0.52
        )
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(t.isLight ? 0.70 : 0.38),
            t.blush.withAlphaComponent(t.isLight ? 0.06 : 0.10),
            NSColor.white.withAlphaComponent(0.0),
        ])?.draw(in: oval(plateSpec), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        let u = rect.width
        let gridPadX = plateRect.width * 0.145
        let gridPadY = plateRect.height * 0.155
        var grid = plateRect.insetBy(dx: gridPadX, dy: gridPadY)
        grid.origin.y += u * 0.012
        let gap = u * 0.032
        let cellW = (grid.width - gap) / 2
        let cellH = (grid.height - gap) / 2
        let cellR = u * 0.058

        struct Cell { let rect: NSRect; let lit: Bool }
        let cells = [
            Cell(rect: NSRect(x: grid.minX, y: grid.minY + cellH + gap, width: cellW, height: cellH), lit: false),
            Cell(rect: NSRect(x: grid.minX + cellW + gap, y: grid.minY + cellH + gap, width: cellW, height: cellH), lit: false),
            Cell(rect: NSRect(x: grid.minX, y: grid.minY, width: cellW, height: cellH), lit: false),
            Cell(rect: NSRect(x: grid.minX + cellW + gap, y: grid.minY, width: cellW, height: cellH), lit: true),
        ]

        for cell in cells {
            let path = rr(cell.rect, cellR)
            softShadow(under: path, dy: -u * 0.012, steps: 5, alpha: t.isLight ? 0.035 : 0.055)

            if cell.lit {
                NSGradient(colorsAndLocations:
                    (NSColor.white.withAlphaComponent(0.85), 0.0),
                    (t.blush, 0.18),
                    (t.coral, 0.42),
                    (t.rose, 0.72),
                    (t.magenta.withAlphaComponent(0.95), 1.0)
                )?.draw(in: path, angle: -48)
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                radial(
                    center: NSPoint(x: cell.rect.midX - cellW * 0.05, y: cell.rect.midY + cellH * 0.08),
                    radius: max(cellW, cellH) * 0.55,
                    colors: [
                        NSColor.white.withAlphaComponent(0.55),
                        t.blush.withAlphaComponent(0.25),
                        t.rose.withAlphaComponent(0.0),
                    ]
                )
                NSGraphicsContext.restoreGraphicsState()
                stroke(path, NSColor.white.withAlphaComponent(0.75), u * 0.005)
                let halo = rr(cell.rect.insetBy(dx: -u * 0.006, dy: -u * 0.006), cellR + u * 0.006)
                stroke(halo, t.rose.withAlphaComponent(0.45), u * 0.004)
            } else if t.isLight {
                softShadow(under: path, dy: -u * 0.01, steps: 4, alpha: 0.08)
                NSGradient(colorsAndLocations:
                    (NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.99, alpha: 1), 0.0),
                    (NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.94, alpha: 1), 0.5),
                    (NSColor(calibratedRed: 0.82, green: 0.80, blue: 0.88, alpha: 1), 1.0)
                )?.draw(in: path, angle: -85)
                stroke(path, NSColor(calibratedRed: 0.55, green: 0.50, blue: 0.65, alpha: 0.38), u * 0.0045)
                stroke(path, NSColor.white.withAlphaComponent(0.75), u * 0.0025)
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                let cs = NSRect(
                    x: cell.rect.minX + cell.rect.width * 0.10,
                    y: cell.rect.maxY - cell.rect.height * 0.58,
                    width: cell.rect.width * 0.80,
                    height: cell.rect.height * 0.52
                )
                NSGradient(colors: [
                    NSColor.white.withAlphaComponent(0.65),
                    NSColor.white.withAlphaComponent(0.0),
                ])?.draw(in: oval(cs), angle: -90)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSGradient(colorsAndLocations:
                    (NSColor.white.withAlphaComponent(t.idleCellTop), 0.0),
                    (t.ice.withAlphaComponent(t.idleCellTop * 0.65), 0.4),
                    (t.iceTint.withAlphaComponent(t.idleCellBot), 1.0)
                )?.draw(in: path, angle: -85)
                fill(path, NSColor.white.withAlphaComponent(0.08))
                stroke(path, NSColor.white.withAlphaComponent(0.42), u * 0.0035)
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                let cs = NSRect(
                    x: cell.rect.minX + cell.rect.width * 0.10,
                    y: cell.rect.maxY - cell.rect.height * 0.58,
                    width: cell.rect.width * 0.80,
                    height: cell.rect.height * 0.52
                )
                NSGradient(colors: [
                    NSColor.white.withAlphaComponent(0.40),
                    NSColor.white.withAlphaComponent(0.0),
                ])?.draw(in: oval(cs), angle: -90)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        let lit = cells[3].rect
        let spark = NSPoint(x: lit.maxX - lit.width * 0.12, y: lit.maxY + u * 0.01)

        radial(center: spark, radius: u * 0.16, colors: [
            t.rose.withAlphaComponent(t.isLight ? 0.48 : 0.55),
            t.magenta.withAlphaComponent(t.isLight ? 0.18 : 0.22),
            t.rose.withAlphaComponent(0.0),
        ])

        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        let trail = NSBezierPath()
        let t0 = NSPoint(x: lit.midX + lit.width * 0.15, y: lit.midY + lit.height * 0.05)
        trail.move(to: t0)
        trail.curve(
            to: spark,
            controlPoint1: NSPoint(x: t0.x + u * 0.05, y: t0.y + u * 0.07),
            controlPoint2: NSPoint(x: spark.x - u * 0.015, y: spark.y - u * 0.05)
        )
        t.rose.withAlphaComponent(0.50).setStroke()
        trail.lineWidth = u * 0.018
        trail.lineCapStyle = .round
        trail.stroke()
        NSColor.white.withAlphaComponent(0.45).setStroke()
        trail.lineWidth = u * 0.006
        trail.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let glints: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (spark.x - u * 0.07, spark.y + u * 0.04, u * 0.022, 0.85),
            (spark.x + u * 0.055, spark.y + u * 0.07, u * 0.015, 0.75),
            (spark.x - u * 0.03, spark.y + u * 0.11, u * 0.011, 0.70),
            (spark.x + u * 0.02, spark.y - u * 0.055, u * 0.010, 0.55),
        ]
        for g in glints {
            let p = sparkPath(center: NSPoint(x: g.0, y: g.1), outer: g.2)
            fill(p, t.coral.withAlphaComponent(g.3))
            fill(p, NSColor.white.withAlphaComponent(0.45))
        }

        let mainOuter = sparkPath(center: spark, outer: u * 0.072, innerRatio: 0.32)
        fill(sparkPath(center: NSPoint(x: spark.x, y: spark.y - u * 0.008), outer: u * 0.078),
             t.rose.withAlphaComponent(0.40))
        NSGradient(colorsAndLocations:
            (NSColor.white, 0.0),
            (t.blush, 0.22),
            (t.coral, 0.48),
            (t.rose, 0.78),
            (t.magenta, 1.0)
        )?.draw(in: mainOuter, angle: -30)
        stroke(mainOuter, NSColor.white.withAlphaComponent(0.85), u * 0.0035)
        radial(center: spark, radius: u * 0.022, colors: [
            NSColor.white, NSColor.white.withAlphaComponent(0.85), t.blush.withAlphaComponent(0.0),
        ])
        fill(oval(NSRect(x: spark.x - u * 0.012, y: spark.y - u * 0.012, width: u * 0.024, height: u * 0.024)),
             NSColor.white)

        if t.isLight {
            stroke(outer, NSColor.white.withAlphaComponent(0.85), u * 0.005)
            let inner = rr(rect.insetBy(dx: u * 0.005, dy: u * 0.005), corner * 0.97)
            stroke(inner, NSColor(calibratedWhite: 0.35, alpha: 0.16), u * 0.0035)
        } else {
            stroke(outer, NSColor.white.withAlphaComponent(0.20), u * 0.005)
            let inner = rr(rect.insetBy(dx: u * 0.005, dy: u * 0.005), corner * 0.97)
            stroke(inner, t.void.withAlphaComponent(0.40), u * 0.0035)
        }

        NSGraphicsContext.saveGraphicsState()
        outer.addClip()
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(t.isLight ? 0.50 : 0.16),
            NSColor.white.withAlphaComponent(0.0),
        ])?.draw(
            in: NSRect(x: rect.minX, y: rect.minY + rect.height * 0.78, width: rect.width, height: rect.height * 0.22),
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
    let darkURL = base.appendingPathComponent("AppIcon.png")
    let lightURL = base.appendingPathComponent("AppIcon-light.png")
    try writePNG(renderIcon(theme: .dark), to: darkURL)
    try writePNG(renderIcon(theme: .light), to: lightURL)
    print("Wrote \(darkURL.path)")
    print("Wrote \(lightURL.path)")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
