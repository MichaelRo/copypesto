// SPDX-License-Identifier: MIT
// Draws the menu-bar template icon at 1x and 2x: `swift design/source/menubar-icon.swift <output dir>`.
import AppKit

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

    // The jar (design board C1, expert panel 2026-11-25), in points on an 18 pt canvas, every edge on a whole pixel
    // at 2x: a lid 8 x 2, a 1.5 gap, a body 12 x 10.5 with shoulders (radius 3.5 at the top, 2 at the base), and a
    // P cut out of the body with a 1.5 stem and a counter of at least 1.5.
    let lid = CGRect(x: 5, y: 14, width: 8, height: 2)
    ctx.addPath(CGPath(roundedRect: lid, cornerWidth: 1, cornerHeight: 1, transform: nil))
    ctx.fillPath()

    let body = CGMutablePath()
    let (left, right, base, top, shoulder, foot) = (3.0, 15.0, 2.0, 12.5, 3.5, 2.0)
    body.move(to: CGPoint(x: left + foot, y: base))
    body.addLine(to: CGPoint(x: right - foot, y: base))
    body.addArc(tangent1End: CGPoint(x: right, y: base), tangent2End: CGPoint(x: right, y: base + foot), radius: foot)
    body.addLine(to: CGPoint(x: right, y: top - shoulder))
    body.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right - shoulder, y: top), radius: shoulder)
    body.addLine(to: CGPoint(x: left + shoulder, y: top))
    body.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left, y: top - shoulder), radius: shoulder)
    body.addLine(to: CGPoint(x: left, y: base + foot))
    body.addArc(tangent1End: CGPoint(x: left, y: base), tangent2End: CGPoint(x: left + foot, y: base), radius: foot)
    body.closeSubpath()
    ctx.addPath(body)
    ctx.fillPath()

    // The P, about half the body's height: stem 1.5 wide; bowl 4 wide and 3.5 tall with a 1.5 x 1.5 counter.
    let stem = CGRect(x: 7, y: 4.5, width: 1.5, height: 6)
    let bowl = CGRect(x: 7, y: 7, width: 4.5, height: 3.5)
    let counter = CGRect(x: 8.5, y: 8, width: 1.5, height: 1.5)
    let letter = CGMutablePath()
    letter.addRect(stem)
    letter.addRoundedRect(in: bowl, cornerWidth: 1.75, cornerHeight: 1.75)
    ctx.setBlendMode(.clear)
    ctx.addPath(letter)
    ctx.fillPath()
    ctx.setBlendMode(.normal)
    ctx.addPath(CGPath(rect: counter, transform: nil))
    ctx.fillPath()
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
