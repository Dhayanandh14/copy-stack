import AppKit

// Background art for the installer window: a soft field, a title, and an arrow
// pointing from where the app icon sits toward the Applications folder.
// Original artwork drawn with Core Graphics.

let width: CGFloat = 640, height: CGFloat = 400
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./dmg-background.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: Int(width), pixelsHigh: Int(height),
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Field
let space = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1),
    CGColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

// Title. Finder places icons at y=200 from the top, so the title sits above them.
let title = "Drag ClipStack into your Applications folder"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.25, alpha: 1),
]
let titleSize = title.size(withAttributes: titleAttrs)
title.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 72), withAttributes: titleAttrs)

let note = "First launch: right-click the app and choose Open"
let noteAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12),
    .foregroundColor: NSColor(calibratedRed: 0.45, green: 0.49, blue: 0.55, alpha: 1),
]
let noteSize = note.size(withAttributes: noteAttrs)
note.draw(at: NSPoint(x: (width - noteSize.width) / 2, y: 46), withAttributes: noteAttrs)

// Arrow between the two icon slots (Finder y=200 from top → y=200 from bottom here).
let y: CGFloat = height - 200
let startX: CGFloat = 258, endX: CGFloat = 382
ctx.setStrokeColor(CGColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1))
ctx.setLineWidth(4)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: startX, y: y))
ctx.addLine(to: CGPoint(x: endX - 14, y: y))
ctx.strokePath()

ctx.setFillColor(CGColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1))
ctx.move(to: CGPoint(x: endX + 6, y: y))
ctx.addLine(to: CGPoint(x: endX - 20, y: y + 13))
ctx.addLine(to: CGPoint(x: endX - 20, y: y - 13))
ctx.closePath()
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()
try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
