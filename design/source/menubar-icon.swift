// SPDX-License-Identifier: MIT
// Draws the menu-bar template icon at 1x and 2x: `swift design/source/menubar-icon.swift <output dir>`.
import AppKit
import CoreText

func render(scale: CGFloat) -> Data {
    let pts: CGFloat = 18
    let px = Int(pts * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let ctx = ns.cgContext
    ctx.scaleBy(x: scale, y: scale)
    ctx.clear(CGRect(x: 0, y: 0, width: pts, height: pts))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.setStrokeColor(NSColor.black.cgColor)

    // Back card: an outline peeking out to the lower right.
    let back = CGRect(x: 4.5, y: 1.5, width: 12, height: 12)
    ctx.setLineWidth(1.5)
    ctx.addPath(CGPath(roundedRect: back.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 3, cornerHeight: 3, transform: nil))
    ctx.strokePath()

    // Clear a gap around the front card so it reads as a separate layer.
    let front = CGRect(x: 1.5, y: 4.5, width: 12, height: 12)
    ctx.setBlendMode(.clear)
    ctx.addPath(CGPath(
        roundedRect: front.insetBy(dx: -1.5, dy: -1.5),
        cornerWidth: 4.5,
        cornerHeight: 4.5,
        transform: nil
    ))
    ctx.fillPath()
    ctx.setBlendMode(.normal)

    // Front card, filled, with a P knocked out of it.
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: 3, cornerHeight: 3, transform: nil))
    ctx.fillPath()
    let font = NSFont.systemFont(ofSize: 11.5, weight: .heavy) as CTFont
    var glyph = CTFontGetGlyphWithName(font, "P" as CFString)
    if glyph == 0 { var chars: [UniChar] = [0x50]
        CTFontGetGlyphsForCharacters(font, &chars, &glyph, 1)
    }
    if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
        let bounds = path.boundingBox
        var t = CGAffineTransform(translationX: front.midX - bounds.midX, y: front.midY - bounds.midY)
        ctx.setBlendMode(.clear)
        ctx.addPath(path.copy(using: &t)!)
        ctx.fillPath()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: swift menubar-icon.swift <output dir>\n".utf8))
    exit(2)
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try render(scale: 1).write(to: folder.appendingPathComponent("menubar@1x.png"))
    try render(scale: 2).write(to: folder.appendingPathComponent("menubar@2x.png"))
    print("ok")
} catch {
    FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
    exit(1)
}
