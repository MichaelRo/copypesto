// SPDX-License-Identifier: MIT
#if DEBUG
    import CoreGraphics
    import Foundation

    extension ShowcaseArt {
        struct ColorStop {
            let hex: String
            let location: CGFloat
            var alpha: CGFloat = 1
        }

        static func gradient(_ stops: [ColorStop]) -> CGGradient? {
            CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map { color(hex: $0.hex, alpha: $0.alpha) } as CFArray,
                locations: stops.map(\.location)
            )
        }

        static func sparkle(_ context: CGContext, at point: CGPoint, radius: CGFloat, hex: String, alpha: CGFloat = 1) {
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius * 0.62, y: 0), control: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: -radius), control: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: -radius * 0.62, y: 0), control: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: radius), control: CGPoint(x: 0, y: 0))
            context.addPath(path)
            context.setFillColor(color(hex: hex, alpha: alpha))
            context.fillPath()
            context.restoreGState()
        }

        static func pineNut(_ context: CGContext, at point: CGPoint, angle: CGFloat, scale: CGFloat) {
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.rotate(by: angle)
            context.scaleBy(x: scale, y: scale)
            let nut = CGRect(x: -26, y: -10, width: 52, height: 20)
            context.setFillColor(color(hex: BrandPalette.pineNut))
            context.fillEllipse(in: nut)
            context.setStrokeColor(color(hex: "C9A56A"))
            context.setLineWidth(2)
            context.strokeEllipse(in: nut)
            context.setFillColor(color(hex: "FFFFFF", alpha: 0.45))
            context.fillEllipse(in: CGRect(x: -16, y: 1, width: 20, height: 5))
            context.restoreGState()
        }

        /// A basil leaf in dark glasses, the first of the Lunch Rush finale pictures: flat shapes with soft light, only
        /// in
        /// the Pesto palette.
        static func basilInSunglasses() -> Data {
            render(width: 960, height: 640) { context in
                drawBasilBackdrop(context)
                context.saveGState()
                context.translateBy(x: 480, y: 316)
                context.rotate(by: -0.2)
                let leaf = basilLeafPath(halfWidth: 228, halfHeight: 252)
                drawBasilLeaf(context, path: leaf, halfHeight: 252)
                drawSunglasses(context)
                drawSmirk(context)
                context.restoreGState()
                sparkle(context, at: CGPoint(x: 735, y: 468), radius: 34, hex: BrandPalette.goldFill)
                sparkle(context, at: CGPoint(x: 790, y: 395), radius: 18, hex: BrandPalette.goldFill, alpha: 0.8)
                sparkle(context, at: CGPoint(x: 205, y: 520), radius: 22, hex: BrandPalette.goldFill, alpha: 0.7)
            }
        }

        /// The same basil leaf with no glasses, in a chef's hat and an apron, pressing its fingertips to its lips for a
        /// chef's
        /// kiss: the film's thank-you sticker.
        static func basilChefsKiss() -> Data {
            render(width: 960, height: 640) { context in
                drawBasilBackdrop(context)
                context.saveGState()
                context.translateBy(x: 480, y: 292)
                context.scaleBy(x: 0.82, y: 0.82)
                context.rotate(by: -0.12)
                let leaf = basilLeafPath(halfWidth: 228, halfHeight: 252)
                drawBasilLeaf(context, path: leaf, halfHeight: 252)
                drawApron(context, clip: leaf)
                drawHappyFace(context)
                drawChefsHat(context)
                drawKissHand(context)
                drawKissFlight(context)
                context.restoreGState()
                sparkle(context, at: CGPoint(x: 735, y: 468), radius: 34, hex: BrandPalette.goldFill)
                sparkle(context, at: CGPoint(x: 790, y: 395), radius: 18, hex: BrandPalette.goldFill, alpha: 0.8)
                sparkle(context, at: CGPoint(x: 205, y: 520), radius: 22, hex: BrandPalette.goldFill, alpha: 0.7)
                sparkle(context, at: CGPoint(x: 720, y: 300), radius: 14, hex: BrandPalette.goldFill, alpha: 0.9)
            }
        }

        private static func drawApron(_ context: CGContext, clip leaf: CGPath) {
            context.saveGState()
            context.addPath(leaf)
            context.clip()
            let apron = CGMutablePath()
            apron.move(to: CGPoint(x: -96, y: -92))
            apron.addLine(to: CGPoint(x: 96, y: -92))
            apron.addLine(to: CGPoint(x: 150, y: -300))
            apron.addLine(to: CGPoint(x: -150, y: -300))
            apron.closeSubpath()
            context.addPath(apron)
            context.setFillColor(color(hex: BrandPalette.garlic))
            context.fillPath()
            context.addPath(apron)
            context.setStrokeColor(color(hex: "D9D4C5"))
            context.setLineWidth(6)
            context.strokePath()
            context.setStrokeColor(color(hex: BrandPalette.accentDark, alpha: 0.45))
            context.setLineWidth(5)
            for x in stride(from: CGFloat(-60), through: 60, by: 40) {
                context.move(to: CGPoint(x: x, y: -100))
                context.addLine(to: CGPoint(x: x * 1.45, y: -300))
                context.strokePath()
            }
            let pocket = CGPath(
                roundedRect: CGRect(x: -52, y: -214, width: 104, height: 62), cornerWidth: 16, cornerHeight: 16,
                transform: nil
            )
            context.addPath(pocket)
            context.setFillColor(color(hex: BrandPalette.parmesan))
            context.fillPath()
            context.addPath(pocket)
            context.setStrokeColor(color(hex: "D9D4C5"))
            context.setLineWidth(5)
            context.strokePath()
            context.restoreGState()
        }

        private static func drawHappyFace(_ context: CGContext) {
            context.setStrokeColor(color(hex: "173F26"))
            context.setLineWidth(12)
            context.setLineCap(.round)
            for x: CGFloat in [-84, 84] {
                context.move(to: CGPoint(x: x - 38, y: 34))
                context.addQuadCurve(to: CGPoint(x: x + 38, y: 34), control: CGPoint(x: x, y: 100))
                context.strokePath()
            }
            context.setFillColor(color(hex: "F4A3A0", alpha: 0.9))
            for x: CGFloat in [-140, 140] {
                context.fillEllipse(in: CGRect(x: x - 26, y: -12, width: 52, height: 30))
            }
            context.setFillColor(color(hex: "173F26"))
            context.fillEllipse(in: CGRect(x: 4, y: -68, width: 46, height: 40))
            context.setFillColor(color(hex: "E58F8F", alpha: 0.9))
            context.fillEllipse(in: CGRect(x: 15, y: -58, width: 24, height: 18))
        }

        private static func drawChefsHat(_ context: CGContext) {
            let cream = color(hex: BrandPalette.garlic)
            let edge = color(hex: "D9D4C5")
            context.setLineWidth(6)
            for center in [CGPoint(x: -62, y: 292), CGPoint(x: 62, y: 292), CGPoint(x: 0, y: 330)] {
                let puff = CGRect(x: center.x - 66, y: center.y - 58, width: 132, height: 116)
                context.setFillColor(cream)
                context.fillEllipse(in: puff)
                context.setStrokeColor(edge)
                context.strokeEllipse(in: puff)
            }
            context.setFillColor(cream)
            context.fill(CGRect(x: -96, y: 232, width: 192, height: 70))
            let band = CGPath(
                roundedRect: CGRect(x: -104, y: 196, width: 208, height: 60), cornerWidth: 18, cornerHeight: 18,
                transform: nil
            )
            context.addPath(band)
            context.setFillColor(cream)
            context.fillPath()
            context.addPath(band)
            context.setStrokeColor(edge)
            context.strokePath()
        }

        private static func drawGlove(
            _ context: CGContext, _ center: CGPoint, _ size: CGSize, _ rotation: CGFloat, shadow: Bool = false
        ) {
            let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: rotation)
            if shadow {
                context.setShadow(
                    offset: CGSize(width: 0, height: -8),
                    blur: 14,
                    color: color(hex: "173F26", alpha: 0.35)
                )
            }
            context.setFillColor(color(hex: "FFFFFF"))
            context.fillEllipse(in: rect)
            context.setStrokeColor(color(hex: "173F26"))
            context.setLineWidth(6)
            context.strokeEllipse(in: rect)
            context.restoreGState()
        }

        private static func drawKissHand(_ context: CGContext) {
            let line = color(hex: "173F26")
            let palm = CGPoint(x: 124, y: -146)
            let tip = CGPoint(x: 58, y: -74)
            let length = hypot(tip.x - palm.x, tip.y - palm.y)
            let unit = CGPoint(x: (tip.x - palm.x) / length, y: (tip.y - palm.y) / length)
            let normal = CGPoint(x: -unit.y, y: unit.x)
            let angle = atan2(unit.y, unit.x)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.setLineWidth(6)

            // four fingers bunched toward the lips, then the palm, then the thumb folded over them
            for baseOffset: CGFloat in [-32, -11, 11, 32] {
                let tipOffset = baseOffset * 0.22
                let mid = (baseOffset + tipOffset) / 2
                let center = CGPoint(
                    x: palm.x + unit.x * length * 0.5 + normal.x * mid,
                    y: palm.y + unit.y * length * 0.5 + normal.y * mid
                )
                drawGlove(
                    context,
                    center,
                    CGSize(width: length + 36, height: 34),
                    angle + atan2(tipOffset - baseOffset, length),
                    shadow: true
                )
            }
            drawGlove(context, palm, CGSize(width: 110, height: 104), angle)
            drawGlove(
                context,
                CGPoint(
                    x: palm.x + unit.x * length * 0.32 - normal.x * 32,
                    y: palm.y + unit.y * length * 0.32 - normal.y * 32
                ),
                CGSize(width: 78, height: 32), angle - 0.45
            )
            let wrist = CGPoint(x: palm.x - unit.x * 58, y: palm.y - unit.y * 58)
            context.saveGState()
            context.translateBy(x: wrist.x, y: wrist.y)
            context.rotate(by: angle + .pi / 2)
            let cuff = CGPath(
                roundedRect: CGRect(x: -44, y: -14, width: 88, height: 30), cornerWidth: 12, cornerHeight: 12,
                transform: nil
            )
            context.addPath(cuff)
            context.setFillColor(color(hex: "246238"))
            context.fillPath()
            context.addPath(cuff)
            context.setStrokeColor(line)
            context.strokePath()
            context.restoreGState()
        }

        private static func drawKissFlight(_ context: CGContext) {
            heart(context, at: CGPoint(x: 150, y: -38), size: 30, hex: "F4A3A0")
            heart(context, at: CGPoint(x: 206, y: 6), size: 22, hex: BrandPalette.goldFill)
            context.setStrokeColor(color(hex: BrandPalette.goldFill))
            context.setLineWidth(9)
            for (from, to) in [
                (CGPoint(x: 92, y: -34), CGPoint(x: 120, y: -14)),
                (CGPoint(x: 98, y: -56), CGPoint(x: 136, y: -56))
            ] {
                context.move(to: from)
                context.addLine(to: to)
                context.strokePath()
            }
        }

        private static func heart(_ context: CGContext, at point: CGPoint, size: CGFloat, hex: String) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: point.x, y: point.y - size * 0.9))
            path.addCurve(
                to: CGPoint(x: point.x - size, y: point.y + size * 0.1),
                control1: CGPoint(x: point.x - size * 0.4, y: point.y - size * 0.6),
                control2: CGPoint(x: point.x - size, y: point.y - size * 0.3)
            )
            path.addCurve(
                to: CGPoint(x: point.x, y: point.y + size * 0.3),
                control1: CGPoint(x: point.x - size, y: point.y + size * 0.7),
                control2: CGPoint(x: point.x - size * 0.2, y: point.y + size * 0.7)
            )
            path.addCurve(
                to: CGPoint(x: point.x + size, y: point.y + size * 0.1),
                control1: CGPoint(x: point.x + size * 0.2, y: point.y + size * 0.7),
                control2: CGPoint(x: point.x + size, y: point.y + size * 0.7)
            )
            path.addCurve(
                to: CGPoint(x: point.x, y: point.y - size * 0.9),
                control1: CGPoint(x: point.x + size, y: point.y - size * 0.3),
                control2: CGPoint(x: point.x + size * 0.4, y: point.y - size * 0.6)
            )
            context.addPath(path)
            context.setFillColor(color(hex: hex))
            context.fillPath()
        }

        private static func drawBasilBackdrop(_ context: CGContext) {
            let size = CGSize(width: context.width, height: context.height)
            if let wash = gradient([
                ColorStop(hex: BrandPalette.garlic, location: 0),
                ColorStop(hex: BrandPalette.parmesan, location: 1)
            ]) {
                context.drawRadialGradient(
                    wash, startCenter: CGPoint(x: size.width / 2, y: size.height * 0.55), startRadius: 0,
                    endCenter: CGPoint(x: size.width / 2, y: size.height * 0.55), endRadius: size.width * 0.62,
                    options: [.drawsAfterEndLocation]
                )
            }
            context.setFillColor(color(hex: BrandPalette.pineNut, alpha: 0.75))
            context.fillEllipse(in: CGRect(x: 480 - 262, y: 322 - 262, width: 524, height: 524))
            context.setStrokeColor(color(hex: BrandPalette.goldFill, alpha: 0.55))
            context.setLineWidth(5)
            context.strokeEllipse(in: CGRect(x: 480 - 288, y: 322 - 288, width: 576, height: 576))
            pineNut(context, at: CGPoint(x: 120, y: 120), angle: 0.5, scale: 1.3)
            pineNut(context, at: CGPoint(x: 200, y: 72), angle: -0.3, scale: 1.0)
            pineNut(context, at: CGPoint(x: 840, y: 150), angle: 0.9, scale: 1.2)
            pineNut(context, at: CGPoint(x: 770, y: 80), angle: -0.6, scale: 0.9)
            pineNut(context, at: CGPoint(x: 96, y: 470), angle: -0.8, scale: 1.0)
        }

        static func basilLeafPath(halfWidth: CGFloat, halfHeight: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -halfHeight * 0.9))
            path.addCurve(
                to: CGPoint(x: 0, y: halfHeight),
                control1: CGPoint(x: halfWidth * 1.25, y: -halfHeight * 0.62),
                control2: CGPoint(x: halfWidth * 0.95, y: halfHeight * 0.5)
            )
            path.addCurve(
                to: CGPoint(x: 0, y: -halfHeight * 0.9),
                control1: CGPoint(x: -halfWidth * 0.95, y: halfHeight * 0.5),
                control2: CGPoint(x: -halfWidth * 1.25, y: -halfHeight * 0.62)
            )
            path.closeSubpath()
            return path
        }

        private static func drawBasilLeaf(_ context: CGContext, path: CGPath, halfHeight: CGFloat) {
            let stem = CGMutablePath()
            stem.addRoundedRect(
                in: CGRect(x: -11, y: -halfHeight * 1.12, width: 22, height: halfHeight * 0.3),
                cornerWidth: 9, cornerHeight: 9
            )
            context.setFillColor(color(hex: "246238"))
            context.addPath(stem)
            context.fillPath()

            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -22),
                blur: 34,
                color: color(hex: BrandPalette.mortar, alpha: 0.32)
            )
            context.addPath(path)
            context.setFillColor(color(hex: BrandPalette.accentLight))
            context.fillPath()
            context.restoreGState()

            context.saveGState()
            context.addPath(path)
            context.clip()
            if let body = gradient([
                ColorStop(hex: "246238", location: 0),
                ColorStop(hex: BrandPalette.accentLight, location: 0.45),
                ColorStop(hex: "4A9D68", location: 0.8),
                ColorStop(hex: BrandPalette.accentDark, location: 1)
            ]) {
                context.drawLinearGradient(
                    body, start: CGPoint(x: -200, y: -halfHeight), end: CGPoint(x: 210, y: halfHeight), options: []
                )
            }
            drawVeins(context, halfHeight: halfHeight)
            context.restoreGState()

            context.addPath(path)
            context.setStrokeColor(color(hex: "1F5A35", alpha: 0.55))
            context.setLineWidth(5)
            context.strokePath()
        }

        private static func drawVeins(_ context: CGContext, halfHeight: CGFloat) {
            context.setLineCap(.round)
            context.setStrokeColor(color(hex: BrandPalette.parmesan, alpha: 0.6))
            context.setLineWidth(8)
            context.move(to: CGPoint(x: 0, y: -halfHeight * 0.95))
            context.addLine(to: CGPoint(x: 0, y: halfHeight * 0.9))
            context.strokePath()
            context.setLineWidth(4)
            context.setStrokeColor(color(hex: BrandPalette.parmesan, alpha: 0.32))
            for index in 0..<5 {
                let base = -halfHeight * 0.62 + CGFloat(index) * halfHeight * 0.34
                for side: CGFloat in [-1, 1] {
                    context.move(to: CGPoint(x: 0, y: base))
                    context.addQuadCurve(
                        to: CGPoint(x: side * (165 - CGFloat(index) * 18), y: base + 104),
                        control: CGPoint(x: side * 46, y: base + 70)
                    )
                    context.strokePath()
                }
            }
        }

        private static func drawSunglasses(_ context: CGContext) {
            let frame = color(hex: "181B19")
            let lensHeight: CGFloat = 112
            let lensWidth: CGFloat = 156
            let centers = [CGPoint(x: -92, y: 42), CGPoint(x: 92, y: 42)]
            context.setStrokeColor(frame)
            context.setLineWidth(11)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: -26, y: 66))
            context.addQuadCurve(to: CGPoint(x: 26, y: 66), control: CGPoint(x: 0, y: 92))
            context.strokePath()
            for side: CGFloat in [-1, 1] {
                context.move(to: CGPoint(x: side * 168, y: 78))
                context.addLine(to: CGPoint(x: side * 204, y: 98))
                context.strokePath()
            }
            for center in centers {
                let lens = CGPath(
                    roundedRect: CGRect(
                        x: center.x - lensWidth / 2,
                        y: center.y - lensHeight / 2,
                        width: lensWidth,
                        height: lensHeight
                    ),
                    cornerWidth: 46, cornerHeight: 46, transform: nil
                )
                context.saveGState()
                context.addPath(lens)
                context.clip()
                if let glass = gradient([
                    ColorStop(hex: "2B2F2A", location: 0),
                    ColorStop(hex: "111412", location: 1)
                ]) {
                    context.drawLinearGradient(
                        glass, start: CGPoint(x: center.x, y: center.y + lensHeight / 2),
                        end: CGPoint(x: center.x, y: center.y - lensHeight / 2), options: []
                    )
                }
                context.setFillColor(color(hex: BrandPalette.accentDark, alpha: 0.18))
                context.fill(CGRect(
                    x: center.x - lensWidth / 2,
                    y: center.y - lensHeight / 2,
                    width: lensWidth,
                    height: lensHeight * 0.4
                ))
                drawLensGlare(context, center: center)
                context.restoreGState()
                context.addPath(lens)
                context.setStrokeColor(frame)
                context.setLineWidth(11)
                context.strokePath()
            }
        }

        private static func drawLensGlare(_ context: CGContext, center: CGPoint) {
            let glare = CGMutablePath()
            glare.move(to: CGPoint(x: center.x - 52, y: center.y + 44))
            glare.addLine(to: CGPoint(x: center.x - 22, y: center.y + 44))
            glare.addLine(to: CGPoint(x: center.x - 62, y: center.y - 30))
            glare.addLine(to: CGPoint(x: center.x - 80, y: center.y - 30))
            glare.closeSubpath()
            context.addPath(glare)
            context.setFillColor(color(hex: "FFFFFF", alpha: 0.3))
            context.fillPath()
            context.setStrokeColor(color(hex: BrandPalette.goldTextDark, alpha: 0.55))
            context.setLineWidth(5)
            context.move(to: CGPoint(x: center.x + 4, y: center.y + 30))
            context.addLine(to: CGPoint(x: center.x + 34, y: center.y + 30))
            context.strokePath()
        }

        private static func drawSmirk(_ context: CGContext) {
            context.setStrokeColor(color(hex: "173F26"))
            context.setLineWidth(11)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: -52, y: -62))
            context.addCurve(
                to: CGPoint(x: 70, y: -52),
                control1: CGPoint(x: -22, y: -100), control2: CGPoint(x: 38, y: -98)
            )
            context.strokePath()
            context.setLineWidth(7)
            context.move(to: CGPoint(x: 78, y: -34))
            context.addLine(to: CGPoint(x: 88, y: -62))
            context.strokePath()
        }
    }
#endif
