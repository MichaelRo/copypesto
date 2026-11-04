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
                struct Line {
                    let text: String
                    let y: CGFloat
                    let size: CGFloat
                    let bold: Bool
                    let hex: String
                }
                func draw(_ line: Line) {
                    let font = CTFontCreateWithName(
                        (line.bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString,
                        line.size,
                        nil
                    )
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex: line.hex)
                    ]
                    let drawn = CTLineCreateWithAttributedString(NSAttributedString(
                        string: line.text,
                        attributes: attributes
                    ))
                    context.textPosition = CGPoint(x: 28, y: line.y)
                    CTLineDraw(drawn, context)
                }
                draw(Line(text: "BOARDING PASS", y: CGFloat(height) - 54, size: 34, bold: true, hex: "FAF7EE"))
                draw(Line(text: "PS 142  GENOA", y: 176, size: 44, bold: true, hex: "2B2F2A"))
                draw(Line(text: "GATE B7", y: 112, size: 52, bold: true, hex: "2F7A49"))
                draw(Line(text: "MAMMA MIA  14:05", y: 52, size: 30, bold: false, hex: "2B2F2A"))
            }
        }
    }
#endif
