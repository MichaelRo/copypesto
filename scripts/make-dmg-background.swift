#!/usr/bin/env swift
// SPDX-License-Identifier: MIT
// Draws the background of the installer disk image: a garlic-cream window, a plate under each icon, a dotted
// basil-green
// arc from the app to Applications that ends in a basil leaf, and one sentence of instruction. 660 x 400 pt at 2x (1320
// x 800 px, 144 dpi) so Finder shows it sharp on a Retina display.
//
//   swift scripts/make-dmg-background.swift path/to/background.png
import AppKit
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-dmg-background.swift <output.png>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])

let scale: CGFloat = 2
let width = 660
let height = 400
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

/// Coordinates below are points from the top-left, like Finder's icon positions.
func y(_ top: CGFloat) -> CGFloat {
    (CGFloat(height) - top) * scale
}

let gradient = CGGradient(
    colorsSpace: space, colors: [color(0xFAF7EE), color(0xF6EFD9)] as CFArray, locations: [0, 1]
)!
context.drawLinearGradient(
    gradient, start: CGPoint(x: 0, y: CGFloat(height) * scale), end: CGPoint(x: 0, y: 0), options: []
)

/// Runs `draw` with the origin at the top-left in points and y growing downward, like Finder's icon positions.
func inTopLeftSpace(_ draw: () -> Void) {
    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(height) * scale)
    context.scaleBy(x: scale, y: -scale)
    draw()
    context.restoreGState()
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, hex: UInt32, alpha: CGFloat = 1, centerY: CGFloat) {
    let font = NSFont.systemFont(ofSize: size * scale, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor(cgColor: color(hex, alpha: alpha)) ?? .black
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, [])
    context.textPosition = CGPoint(x: (CGFloat(width) * scale - bounds.width) / 2, y: y(centerY) - font.capHeight / 2)
    CTLineDraw(line, context)
}

/// A basil leaf from its stem at the origin to its tip at (length, 0).
func leafPath(length: CGFloat, width leafWidth: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: .zero)
    path.addCurve(
        to: CGPoint(x: length, y: 0),
        control1: CGPoint(x: length * 0.25, y: -leafWidth * 1.25),
        control2: CGPoint(x: length * 0.8, y: -leafWidth * 0.8)
    )
    path.addCurve(
        to: .zero,
        control1: CGPoint(x: length * 0.8, y: leafWidth * 0.8),
        control2: CGPoint(x: length * 0.25, y: leafWidth * 1.25)
    )
    path.closeSubpath()
    return path
}

func leaf(
    at point: CGPoint,
    angle: CGFloat,
    length: CGFloat,
    width leafWidth: CGFloat,
    hex: UInt32,
    alpha: CGFloat = 1
) {
    inTopLeftSpace {
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: angle)
        context.setFillColor(color(hex, alpha: alpha))
        context.addPath(leafPath(length: length, width: leafWidth))
        context.fillPath()
        context.setStrokeColor(color(0xFAF7EE, alpha: 0.55 * alpha))
        context.setLineWidth(max(0.8, length / 38))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: length * 0.08, y: 0))
        context.addLine(to: CGPoint(x: length * 0.86, y: 0))
        context.strokePath()
        context.restoreGState()
    }
}

// Soft basil shapes in the corners, so the window feels like a kitchen table rather than a form.
inTopLeftSpace {
    context.setFillColor(color(0x2F7A49, alpha: 0.055))
    context.fillEllipse(in: CGRect(x: -90, y: 250, width: 260, height: 260))
    context.setFillColor(color(0xC9A227, alpha: 0.09))
    context.fillEllipse(in: CGRect(x: 520, y: -70, width: 220, height: 220))
}

leaf(at: CGPoint(x: 28, y: 372), angle: -0.9, length: 62, width: 17, hex: 0x2F7A49, alpha: 0.28)
leaf(at: CGPoint(x: 52, y: 380), angle: -0.35, length: 48, width: 13, hex: 0x2F7A49, alpha: 0.2)
leaf(at: CGPoint(x: 632, y: 372), angle: .pi + 0.9, length: 62, width: 17, hex: 0x2F7A49, alpha: 0.28)
leaf(at: CGPoint(x: 608, y: 380), angle: .pi + 0.35, length: 48, width: 13, hex: 0x2F7A49, alpha: 0.2)

text("Drag Pesto into Applications", size: 26, weight: .bold, hex: 0x2B2F2A, centerY: 58)
text(
    "That is the whole install. Then open it from there.",
    size: 14,
    weight: .regular,
    hex: 0x2B2F2A,
    alpha: 0.62,
    centerY: 90
)

// A plate under each icon (icon centres at x 170 and 490, y 190).
inTopLeftSpace {
    for centerX in [CGFloat(170), 490] {
        let plate = CGRect(x: centerX - 76, y: 190 - 76, width: 152, height: 152)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: color(0x2B2F2A, alpha: 0.12))
        context.setFillColor(color(0xFFFFFF, alpha: 0.7))
        context.fillEllipse(in: plate)
        context.restoreGState()
        context.setStrokeColor(color(0x2F7A49, alpha: 0.16))
        context.setLineWidth(1.5)
        context.strokeEllipse(in: plate.insetBy(dx: 0.75, dy: 0.75))
    }
}

// The way across: a dotted arc over the gap that ends in a basil leaf pointing at Applications.
let start = CGPoint(x: 252, y: 160)
let control1 = CGPoint(x: 276, y: 112)
let control2 = CGPoint(x: 326, y: 112)
let end = CGPoint(x: 356, y: 146)
inTopLeftSpace {
    context.setStrokeColor(color(0x2F7A49))
    context.setLineWidth(5)
    context.setLineCap(.round)
    context.setLineDash(phase: 0, lengths: [0.1, 11])
    context.move(to: start)
    context.addCurve(to: end, control1: control1, control2: control2)
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])
}

let tangent = atan2(end.y - control2.y, end.x - control2.x)
leaf(
    at: CGPoint(x: end.x - 4 * cos(tangent), y: end.y - 4 * sin(tangent)),
    angle: tangent,
    length: 58,
    width: 21,
    hex: 0x2F7A49
)

text(
    "Pesto keeps your clipboard history on this Mac.",
    size: 12,
    weight: .regular,
    hex: 0x2B2F2A,
    alpha: 0.45,
    centerY: 338
)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
let properties: [CFString: Any] = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
CGImageDestinationAddImage(destination, image, properties as CFDictionary)
guard CGImageDestinationFinalize(destination) else { exit(1) }
