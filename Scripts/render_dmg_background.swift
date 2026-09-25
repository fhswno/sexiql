import AppKit

let width = 660
let height = 400

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width * 2,
    pixelsHigh: height * 2,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
context.setShouldAntialias(true)

let gradient = NSGradient(
    starting: NSColor(calibratedWhite: 0.985, alpha: 1),
    ending: NSColor(calibratedWhite: 0.935, alpha: 1)
)!
gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

let arrowColor = NSColor(calibratedWhite: 0.66, alpha: 1)
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 296, y: 232))
shaft.line(to: NSPoint(x: 364, y: 232))
shaft.lineWidth = 3.5
shaft.lineCapStyle = .round
arrowColor.setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 352, y: 220))
head.line(to: NSPoint(x: 365, y: 232))
head.line(to: NSPoint(x: 352, y: 244))
head.lineWidth = 3.5
head.lineCapStyle = .round
head.lineJoinStyle = .round
arrowColor.setStroke()
head.stroke()

NSGraphicsContext.restoreGraphicsState()

let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let output = repo.appendingPathComponent("Assets/dmg-background.png")
try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: output)
print("wrote \(output.path)")
