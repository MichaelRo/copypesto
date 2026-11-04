// SPDX-License-Identifier: MIT
#if DEBUG
    import CoreGraphics
    import CoreText
    import Foundation

    extension ShowcaseArt {
        /// A screenshot of a boarding pass whose words are large enough for text recognition to read back, so the film
        /// can find it by typing "gate".
        static func boardingPass() -> Data {
            render { context in
                fill(context, hex: "FAF7EE")
                context.setFillColor(color(hex: "2F7A49"))
                context.fill(CGRect(x: 0, y: CGFloat(height) - 78, width: CGFloat(width), height: 78))
                func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool, hex: String) {
                    let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex: hex)
                    ]
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                    context.textPosition = CGPoint(x: x, y: y)
                    CTLineDraw(line, context)
                }
                draw("BOARDING PASS", x: 28, y: CGFloat(height) - 54, size: 34, bold: true, hex: "FAF7EE")
                draw("PS 142", x: 28, y: 176, size: 44, bold: true, hex: "2B2F2A")
                draw("GATE B7", x: 28, y: 112, size: 52, bold: true, hex: "2F7A49")
                draw("BOARDS 14:05", x: 28, y: 52, size: 30, bold: false, hex: "2B2F2A")
            }
        }
    }
#endif
