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
