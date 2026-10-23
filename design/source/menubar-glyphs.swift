// SPDX-License-Identifier: MIT
import AppKit

// Draws the menu-bar glyphs for "history locked", "clip contents hidden" and "capturing paused" from the standing
// glyph:
// the same mark with a padlock, the three dots of a masked clip or a pause sign cut into its lower right corner.
// Template images, so the system
// tints them.
// Usage: swift design/source/menubar-glyphs.swift <imagesets folder>
let arguments = CommandLine.arguments
guard arguments.count == 2 else { fatalError("usage: menubar-glyphs.swift <Assets.xcassets folder>") }
let assets = URL(fileURLWithPath: arguments[1])
let base = assets.appendingPathComponent("MenuBarIcon.imageset/menubar@2x.png")
guard let baseImage = NSImage(contentsOf: base),
      let baseRep = baseImage.representations.first as? NSBitmapImageRep else { fatalError("no base glyph") }

func render(symbol: String, pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill(using: .copy)
    baseRep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))

    let scale = CGFloat(pixels) / 36
    let badge = NSRect(x: 17 * scale, y: 0, width: 19 * scale, height: 19 * scale)
    // A gap around the badge keeps it readable against the mark.
    NSGraphicsContext.current?.compositingOperation = .clear
    NSBezierPath(ovalIn: badge.insetBy(dx: -1.5 * scale, dy: -1.5 * scale)).fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
    NSColor.black.setFill()
    NSBezierPath(ovalIn: badge).fill()

    let configuration = NSImage.SymbolConfiguration(pointSize: 9.5 * scale, weight: .heavy)
    if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    {
        let size = glyph.size
        let target = NSRect(
            x: badge.midX - size.width / 2, y: badge.midY - size.height / 2, width: size.width, height: size.height
        )
        NSGraphicsContext.current?.compositingOperation = .clear
        glyph.draw(in: target, from: .zero, operation: .destinationOut, fraction: 1)
        // destinationOut removes the glyph's shape from the black disc, leaving it as a transparent cut-out.
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ name: String, symbol: String) throws {
    let folder = assets.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (suffix, pixels) in [("@1x", 18), ("@2x", 36)] {
        let data = render(symbol: symbol, pixels: pixels).representation(using: .png, properties: [:])!
        try data.write(to: folder.appendingPathComponent("\(name)\(suffix).png"))
    }
    let contents = """
    {
      "images" : [
        { "filename" : "\(name)@1x.png", "idiom" : "mac", "scale" : "1x" },
        { "filename" : "\(name)@2x.png", "idiom" : "mac", "scale" : "2x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "template-rendering-intent" : "template" }
    }
    """
    try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

try write("MenuBarIconLocked", symbol: "lock.fill")
try write("MenuBarIconHidden", symbol: "ellipsis")
try write("MenuBarIconPaused", symbol: "pause.fill")
