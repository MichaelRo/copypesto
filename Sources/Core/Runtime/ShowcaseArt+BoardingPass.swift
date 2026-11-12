// SPDX-License-Identifier: MIT
#if DEBUG
    import CoreGraphics
    import CoreText
    import Foundation

    extension ShowcaseArt {
        /// A screenshot of a boarding pass whose words are large enough for text recognition to read back, so the film
        /// can find it by typing "gate". It has a card's own proportions, because a picture fills its card, and the
        /// band under the card's header is deep enough for the title to stay clear of it.
        static func boardingPass() -> Data {
            let (passWidth, passHeight): (CGFloat, CGFloat) = (480, 432)
            return render(width: Int(passWidth), height: Int(passHeight)) { context in
                context.setFillColor(color(hex: "FAF7EE"))
                context.fill(CGRect(x: 0, y: 0, width: passWidth, height: passHeight))
                context.setFillColor(color(hex: "2F7A49"))
                context.fill(CGRect(x: 0, y: passHeight - 170, width: passWidth, height: 170))
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
                draw(Line(text: "BOARDING PASS", y: passHeight - 152, size: 34, bold: true, hex: "FAF7EE"))
                draw(Line(text: "PS 142  GENOA", y: 196, size: 40, bold: true, hex: "2B2F2A"))
                draw(Line(text: "GATE B7", y: 126, size: 54, bold: true, hex: "2F7A49"))
                draw(Line(text: "MAMMA MIA  2:05 PM", y: 78, size: 26, bold: false, hex: "2B2F2A"))
            }
        }
    }
#endif
