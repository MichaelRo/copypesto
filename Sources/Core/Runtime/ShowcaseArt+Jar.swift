// SPDX-License-Identifier: MIT
import CoreGraphics
import CoreText
import Foundation

extension ShowcaseArt {
    static let jarFrameSize = CGSize(width: 640, height: 428)

    /// One frame of a jar of pesto being stirred, `progress` 0 to 1 and looping: the spoon circles, the jar rocks a
    /// little, the swirl on top turns and a pine nut rides round it. Only the Pesto palette.
    static func pestoJarFrame(progress: Double) -> CGImage? {
        renderImage(width: Int(jarFrameSize.width), height: Int(jarFrameSize.height)) { context in
            let turn = CGFloat(progress) * 2 * .pi
            drawJarBackdrop(context)
            drawJarLid(context)
            context.saveGState()
            context.translateBy(x: 320, y: 70)
            context.rotate(by: 0.028 * sin(turn))
            context.translateBy(x: -320, y: -70)
            let body = CGPath(
                roundedRect: CGRect(x: 205, y: 70, width: 230, height: 232), cornerWidth: 46, cornerHeight: 46,
                transform: nil
            )
            drawJarContents(context, body: body, turn: turn)
            drawJarGlass(context, body: body)
            drawJarLabel(context)
            context.restoreGState()
        }
    }

    private static func drawJarBackdrop(_ context: CGContext) {
        if let wash = gradient([
            ColorStop(hex: BrandPalette.garlic, location: 0),
            ColorStop(hex: BrandPalette.parmesan, location: 1)
        ]) {
            context.drawRadialGradient(
                wash, startCenter: CGPoint(x: 320, y: 230), startRadius: 0,
                endCenter: CGPoint(x: 320, y: 230), endRadius: 420, options: [.drawsAfterEndLocation]
            )
        }
        context.setFillColor(color(hex: BrandPalette.pineNut, alpha: 0.8))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 74))
        context.setStrokeColor(color(hex: BrandPalette.goldFill, alpha: 0.5))
        context.setLineWidth(3)
        context.move(to: CGPoint(x: 0, y: 74))
        context.addLine(to: CGPoint(x: 640, y: 74))
        context.strokePath()
        context.setFillColor(color(hex: BrandPalette.mortar, alpha: 0.16))
        context.fillEllipse(in: CGRect(x: 170, y: 52, width: 300, height: 34))
        pineNut(context, at: CGPoint(x: 548, y: 44), angle: 0.4, scale: 0.8)
        pineNut(context, at: CGPoint(x: 590, y: 28), angle: -0.5, scale: 0.6)
    }

    private static func drawJarLid(_ context: CGContext) {
        context.saveGState()
        context.translateBy(x: 112, y: 100)
        context.rotate(by: 0.1)
        let lid = CGPath(
            roundedRect: CGRect(x: -78, y: -22, width: 156, height: 44), cornerWidth: 12, cornerHeight: 12,
            transform: nil
        )
        context.setShadow(
            offset: CGSize(width: 0, height: -6),
            blur: 10,
            color: color(hex: BrandPalette.mortar, alpha: 0.3)
        )
        context.addPath(lid)
        context.setFillColor(color(hex: BrandPalette.goldFill))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.translateBy(x: 112, y: 100)
        context.rotate(by: 0.1)
        context.addPath(lid)
        context.clip()
        if let metal = gradient([
            ColorStop(hex: BrandPalette.goldTextDark, location: 0),
            ColorStop(hex: BrandPalette.goldFill, location: 0.55),
            ColorStop(hex: "9C7E1B", location: 1)
        ]) {
            context.drawLinearGradient(metal, start: CGPoint(x: 0, y: 22), end: CGPoint(x: 0, y: -22), options: [])
        }
        context.setStrokeColor(color(hex: "7A5F00", alpha: 0.35))
        context.setLineWidth(3)
        for index in 0..<14 {
            let x = -72 + CGFloat(index) * 11
            context.move(to: CGPoint(x: x, y: -20))
            context.addLine(to: CGPoint(x: x, y: 18))
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawJarContents(_ context: CGContext, body: CGPath, turn: CGFloat) {
        context.saveGState()
        context.addPath(body)
        context.setFillColor(color(hex: "FFFFFF", alpha: 0.35))
        context.fillPath()
        context.addPath(body)
        context.clip()
        let level: CGFloat = 262
        if let pesto = gradient([
            ColorStop(hex: "246238", location: 0),
            ColorStop(hex: BrandPalette.accentLight, location: 0.6),
            ColorStop(hex: "3F8F5B", location: 1)
        ]) {
            context.saveGState()
            context.clip(to: CGRect(x: 190, y: 60, width: 260, height: level - 60))
            context.drawLinearGradient(pesto, start: CGPoint(x: 0, y: 70), end: CGPoint(x: 0, y: level), options: [])
            context.restoreGState()
        }
        let surface = CGRect(x: 320 - 112, y: level - 26, width: 224, height: 52)
        if let top = gradient([
            ColorStop(hex: "4A9D68", location: 0),
            ColorStop(hex: BrandPalette.accentDark, location: 1)
        ]) {
            context.saveGState()
            context.addEllipse(in: surface)
            context.clip()
            context.drawLinearGradient(
                top,
                start: CGPoint(x: 220, y: level - 26),
                end: CGPoint(x: 420, y: level + 26),
                options: []
            )
            context.restoreGState()
        }
        drawSwirl(context, center: CGPoint(x: 320, y: level), turn: turn)
        let orbit = CGPoint(x: 320 + cos(turn + 2.2) * 74, y: level + sin(turn + 2.2) * 16)
        pineNut(context, at: orbit, angle: turn, scale: 0.5)
        context.restoreGState()
        drawSpoon(context, turn: turn, level: level)
    }

    private static func drawSwirl(_ context: CGContext, center: CGPoint, turn: CGFloat) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: 1, y: 0.23)
        context.rotate(by: turn)
        context.setLineCap(.round)
        for arm in 0..<3 {
            context.saveGState()
            context.rotate(by: CGFloat(arm) * 2 * .pi / 3)
            let path = CGMutablePath()
            for step in 0...40 {
                let fraction = CGFloat(step) / 40
                let angle = fraction * 2.4
                let radius = 14 + fraction * 84
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.addPath(path)
            context.setStrokeColor(color(hex: BrandPalette.parmesan, alpha: 0.5))
            context.setLineWidth(11)
            context.strokePath()
            context.restoreGState()
        }
        context.setFillColor(color(hex: BrandPalette.goldTextDark, alpha: 0.55))
        for spot in [CGPoint(x: -60, y: 18), CGPoint(x: 48, y: -26), CGPoint(x: 8, y: 52)] {
            context.fillEllipse(in: CGRect(x: spot.x - 12, y: spot.y - 12, width: 24, height: 24))
        }
        context.restoreGState()
    }

    private static func drawSpoon(_ context: CGContext, turn: CGFloat, level: CGFloat) {
        let head = CGPoint(x: 320 + cos(turn) * 36, y: level - 6 + sin(turn) * 9)
        let angle: CGFloat = 1.12 + 0.1 * sin(turn)
        context.saveGState()
        context.translateBy(x: head.x, y: head.y)
        context.rotate(by: angle - .pi / 2)
        context.setLineCap(.round)
        context.setStrokeColor(color(hex: "9C7E1B"))
        context.setLineWidth(23)
        context.move(to: CGPoint(x: 0, y: 8))
        context.addLine(to: CGPoint(x: 0, y: 250))
        context.strokePath()
        context.setStrokeColor(color(hex: BrandPalette.goldTextDark))
        context.setLineWidth(13)
        context.move(to: CGPoint(x: -2, y: 10))
        context.addLine(to: CGPoint(x: -2, y: 248))
        context.strokePath()
        context.setFillColor(color(hex: BrandPalette.goldFill))
        context.fillEllipse(in: CGRect(x: -22, y: -34, width: 44, height: 62))
        context.setFillColor(color(hex: BrandPalette.accentDark))
        context.fillEllipse(in: CGRect(x: -15, y: -26, width: 30, height: 38))
        context.restoreGState()
    }

    private static func drawJarGlass(_ context: CGContext, body: CGPath) {
        context.saveGState()
        context.addPath(body)
        context.setStrokeColor(color(hex: BrandPalette.mortar, alpha: 0.3))
        context.setLineWidth(5)
        context.strokePath()
        let neck = CGPath(
            roundedRect: CGRect(x: 218, y: 292, width: 204, height: 26), cornerWidth: 9, cornerHeight: 9, transform: nil
        )
        context.addPath(neck)
        context.setFillColor(color(hex: "FFFFFF", alpha: 0.55))
        context.fillPath()
        context.addPath(neck)
        context.setStrokeColor(color(hex: BrandPalette.mortar, alpha: 0.3))
        context.setLineWidth(4)
        context.strokePath()
        for streak in [CGRect(x: 222, y: 116, width: 13, height: 150), CGRect(x: 408, y: 150, width: 7, height: 80)] {
            context.addPath(CGPath(
                roundedRect: streak,
                cornerWidth: streak.width / 2,
                cornerHeight: streak.width / 2,
                transform: nil
            ))
            context.setFillColor(color(hex: "FFFFFF", alpha: streak.width > 10 ? 0.55 : 0.3))
            context.fillPath()
        }
        context.restoreGState()
    }

    private static func drawJarLabel(_ context: CGContext) {
        let label = CGPath(
            roundedRect: CGRect(x: 238, y: 104, width: 164, height: 108), cornerWidth: 12, cornerHeight: 12,
            transform: nil
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -2),
            blur: 5,
            color: color(hex: BrandPalette.mortar, alpha: 0.25)
        )
        context.addPath(label)
        context.setFillColor(color(hex: BrandPalette.garlic))
        context.fillPath()
        context.restoreGState()
        context.addPath(label)
        context.setStrokeColor(color(hex: BrandPalette.goldFill))
        context.setLineWidth(3)
        context.strokePath()
        centeredText(
            context, "PESTO", style: TextStyle(fontName: "HelveticaNeue-Bold", size: 42, hex: BrandPalette.accentLight),
            at: CGPoint(x: 320, y: 152)
        )
        centeredText(
            context, "best before: tonight",
            style: TextStyle(fontName: "HelveticaNeue-Italic", size: 15, hex: BrandPalette.stone),
            at: CGPoint(x: 320, y: 126)
        )
        sparkle(context, at: CGPoint(x: 320, y: 192), radius: 9, hex: BrandPalette.goldFill)
    }

    struct TextStyle {
        let fontName: String
        let size: CGFloat
        let hex: String
    }

    private static func line(_ text: String, _ style: TextStyle) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                style.fontName as CFString,
                style.size,
                nil
            ),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex: style.hex)
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    static func centeredText(_ context: CGContext, _ text: String, style: TextStyle, at center: CGPoint) {
        let line = line(text, style)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        context.textPosition = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, context)
    }

    static func leftText(_ context: CGContext, _ text: String, style: TextStyle, at origin: CGPoint) {
        context.textPosition = origin
        CTLineDraw(line(text, style), context)
    }
}
