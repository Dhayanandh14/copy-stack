import AppKit

// Draws the ClipStack app icon: a stack of clipped cards on a slate-to-blue
// field. Rendered at every size macOS asks for, then packed into an .icns.
// Original artwork, drawn with Core Graphics — no external assets.

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    let s = size / 1024.0   // everything below is authored at 1024pt

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Rounded-square field, inset the way macOS icons sit in their canvas.
    let inset: CGFloat = 100 * s
    let side = 1024 * s - inset * 2
    let field = CGRect(x: inset, y: inset, width: side, height: side)
    let fieldPath = CGPath(roundedRect: field,
                           cornerWidth: 185 * s, cornerHeight: 185 * s,
                           transform: nil)

    ctx.saveGState()
    ctx.addPath(fieldPath)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.29, green: 0.52, blue: 0.86, alpha: 1),   // top, blue
        CGColor(red: 0.13, green: 0.19, blue: 0.30, alpha: 1),   // bottom, slate
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: field.midX, y: field.maxY),
                           end: CGPoint(x: field.midX, y: field.minY),
                           options: [])
    ctx.restoreGState()

    // Three stacked cards, back to front.
    let cardW = 400 * s, cardH = 500 * s
    let centre = CGPoint(x: 512 * s, y: 500 * s)
    let layers: [(dx: CGFloat, dy: CGFloat, alpha: CGFloat)] = [
        (-78, -58, 0.28),
        (-40, -28, 0.52),
        (0, 0, 1.0),
    ]

    for layer in layers {
        let rect = CGRect(x: centre.x - cardW / 2 + layer.dx * s,
                          y: centre.y - cardH / 2 + layer.dy * s,
                          width: cardW, height: cardH)
        let path = CGPath(roundedRect: rect,
                          cornerWidth: 54 * s, cornerHeight: 54 * s, transform: nil)
        ctx.saveGState()
        if layer.alpha == 1.0 {
            ctx.setShadow(offset: CGSize(width: 0, height: -14 * s),
                          blur: 34 * s,
                          color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
        }
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: layer.alpha))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // The clip at the head of the front card.
    let frontRect = CGRect(x: centre.x - cardW / 2, y: centre.y - cardH / 2,
                           width: cardW, height: cardH)
    let clipW = 196 * s, clipH = 92 * s
    let clip = CGRect(x: frontRect.midX - clipW / 2,
                      y: frontRect.maxY - clipH / 2 - 16 * s,
                      width: clipW, height: clipH)
    ctx.addPath(CGPath(roundedRect: clip, cornerWidth: 30 * s, cornerHeight: 30 * s,
                       transform: nil))
    ctx.setFillColor(CGColor(red: 0.16, green: 0.23, blue: 0.36, alpha: 1))
    ctx.fillPath()

    // Text lines on the front card, suggesting a captured clip.
    let lineX = frontRect.minX + 64 * s
    let widths: [CGFloat] = [250, 272, 190]
    for (i, w) in widths.enumerated() {
        let y = frontRect.maxY - (190 + CGFloat(i) * 86) * s
        let line = CGRect(x: lineX, y: y, width: w * s, height: 34 * s)
        ctx.addPath(CGPath(roundedRect: line, cornerWidth: 17 * s, cornerHeight: 17 * s,
                           transform: nil))
        ctx.setFillColor(CGColor(red: 0.42, green: 0.49, blue: 0.60, alpha: 1))
        ctx.fillPath()
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, _ pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
                                     pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for v in variants {
    guard let data = png(NSImage(), v.px) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(v.name).png"))
}
// A standalone 1024 for the README and the DMG background.
try? png(NSImage(), 1024)?.write(to: URL(fileURLWithPath: "\(outDir)/../icon-1024.png"))
print("wrote \(variants.count) sizes to \(outDir)")
