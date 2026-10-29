// SPDX-License-Identifier: MIT
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Small pictures drawn in code for the demo clips, so screenshots show pictures that belong to the sample story
/// without shipping or borrowing any artwork.
enum ShowcaseArt {
    static let width = 480
    static let height = 320

    static func basilLeaves() -> Data {
        render { context in
            fill(context, hex: "F6EFD9")
            struct Leaf {
                let x: CGFloat
                let y: CGFloat
                let angle: CGFloat
                let scale: CGFloat
                let hex: String
            }
            let leaves = [
                Leaf(x: 150, y: 150, angle: 0.35, scale: 1.0, hex: "2F7A49"),
                Leaf(x: 300, y: 175, angle: -0.45, scale: 1.15, hex: "3F8F5B"),
                Leaf(x: 235, y: 110, angle: 1.35, scale: 0.8, hex: "6DBE85")
            ]
            for leaf in leaves {
                context.saveGState()
                context.translateBy(x: leaf.x, y: leaf.y)
                context.rotate(by: leaf.angle)
                context.scaleBy(x: leaf.scale, y: leaf.scale)
                drawLeaf(context, hex: leaf.hex)
                context.restoreGState()
            }
        }
    }

    static func pineNuts() -> Data {
        render { context in
            fill(context, hex: "FAF7EE")
            var seed: UInt32 = 20_260_926
            func next() -> CGFloat {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return CGFloat(seed >> 8) / CGFloat(1 << 24)
            }
            for _ in 0..<34 {
                context.saveGState()
                context.translateBy(x: 30 + next() * 420, y: 30 + next() * 260)
                context.rotate(by: next() * .pi)
                let nut = CGRect(x: -22, y: -8, width: 44, height: 16)
                context.setFillColor(color(hex: "EBD9B4"))
                context.fillEllipse(in: nut)
                context.setStrokeColor(color(hex: "C9A56A"))
                context.setLineWidth(1.5)
                context.strokeEllipse(in: nut)
                context.restoreGState()
            }
        }
    }

    /// A recipe card with words large enough for text recognition to read back, so searching the text inside
    /// pictures can be shown.
    static func recipeCard() -> Data {
        render { context in
            fill(context, hex: "F6EFD9")
            struct Line {
                let text: String
                let size: CGFloat
                let bold: Bool
            }
            let lines = [
                Line(text: "Pesto for four", size: 36, bold: true), Line(text: "basil 60 g", size: 28, bold: false),
                Line(text: "pine nuts 50 g", size: 28, bold: false), Line(
                    text: "garlic 1 clove",
                    size: 28,
                    bold: false
                ),
                Line(text: "olive oil 100 ml", size: 28, bold: false), Line(
                    text: "hard cheese 40 g",
                    size: 28,
                    bold: false
                )
            ]
            var baseline = CGFloat(height) - 58
            for line in lines {
                let (text, size, bold) = (line.text, line.size, line.bold)
                let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex: "2B2F2A")
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                context.textPosition = CGPoint(x: 36, y: baseline)
                CTLineDraw(line, context)
                baseline -= size + 14
            }
        }
    }

    static func ingredientPalette() -> Data {
        render { context in
            let bands = ["2F7A49", "EBD9B4", "F6EFD9", "C9A227", "2B2F2A"]
            let bandWidth = CGFloat(width) / CGFloat(bands.count)
            for (index, hex) in bands.enumerated() {
                context.setFillColor(color(hex: hex))
                context.fill(CGRect(x: CGFloat(index) * bandWidth, y: 0, width: bandWidth + 1, height: CGFloat(height)))
            }
        }
    }

    private static func drawLeaf(_ context: CGContext, hex: String) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -70))
        path.addCurve(to: CGPoint(x: 0, y: 95), control1: CGPoint(x: 80, y: -40), control2: CGPoint(x: 70, y: 60))
        path.addCurve(to: CGPoint(x: 0, y: -70), control1: CGPoint(x: -70, y: 60), control2: CGPoint(x: -80, y: -40))
        context.addPath(path)
        context.setFillColor(color(hex: hex))
        context.fillPath()
        context.setStrokeColor(color(hex: "F6EFD9", alpha: 0.7))
        context.setLineWidth(3)
        context.move(to: CGPoint(x: 0, y: -60))
        context.addLine(to: CGPoint(x: 0, y: 92))
        context.strokePath()
    }

    static func fill(_ context: CGContext, hex: String) {
        context.setFillColor(color(hex: hex))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func color(hex: String, alpha: CGFloat = 1) -> CGColor {
        let parsed = HexColorParser.parse(hex) ?? HexColorComponents(red: 0, green: 0, blue: 0)
        return CGColor(
            srgbRed: CGFloat(parsed.red),
            green: CGFloat(parsed.green),
            blue: CGFloat(parsed.blue),
            alpha: alpha
        )
    }

    static func render(
        width: Int = ShowcaseArt.width, height: Int = ShowcaseArt.height, _ draw: (CGContext) -> Void
    ) -> Data {
        guard let image = renderImage(width: width, height: height, draw) else { return Data() }
        let output = NSMutableData()
        let png = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, png, 1, nil) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : Data()
    }

    static func renderImage(width: Int, height: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(context)
        return context.makeImage()
    }
}
