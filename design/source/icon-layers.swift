// SPDX-License-Identifier: MIT
import AppKit

/// Generates the vector layers for Pesto.icon: run `swift design/source/icon-layers.swift <output dir>`.
///
/// The mark is a jar (design board, 2026-11-25, "C1"): a garlic lid and a garlic body with a gap of ground between
/// them, and the P on the body. The menu bar's template is the same silhouette (`menubar-icon.swift`).
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func roundedRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double) -> String {
    let r = radius
    let (l, t, rr, b) = (x, y, x + width, y + height)
    return "M\(l + r),\(t) H\(rr - r) A\(r),\(r) 0 0 1 \(rr),\(t + r) V\(b - r) A\(r),\(r) 0 0 1 \(rr - r),\(b) "
        + "H\(l + r) A\(r),\(r) 0 0 1 \(l),\(b - r) V\(t + r) A\(r),\(r) 0 0 1 \(l + r),\(t) Z"
}

/// A rounded rectangle with one radius at the top and another at the bottom: the jar's shoulders round in more than its
/// base, so it reads as a jar and not a bin (expert panel, 2026-11-25).
func shoulderedRect(
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double,
    top: Double,
    bottom: Double
)
-> String {
    let (l, t, r, b) = (x, y, x + width, y + height)
    return "M\(l + top),\(t) H\(r - top) A\(top),\(top) 0 0 1 \(r),\(t + top) V\(b - bottom) "
        + "A\(bottom),\(bottom) 0 0 1 \(r - bottom),\(b) H\(l + bottom) A\(bottom),\(bottom) 0 0 1 \(l),\(b - bottom) "
        + "V\(t + top) A\(top),\(top) 0 0 1 \(l + top),\(t) Z"
}

func svg(_ body: String) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\(body)</svg>\n"
}

/// The jar's geometry on the 1024 canvas, shared with `menubar-icon.swift` by value: a body 60% of the canvas wide with
/// shoulders (top radius 30% of its width, base 16%), a lid 72% of the body's width and 11% of the canvas tall, and a
/// 66 px gap between them, which is still a pixel at 20 px.
let body = (x: 205.0, y: 341.0, width: 614.0, height: 520.0, top: 184.0, bottom: 98.0)
let lid = (x: 291.0, y: 162.0, width: 442.0, height: 113.0, radius: 56.5)

let lidLayer = "<path d=\"\(roundedRect(lid.x, lid.y, lid.width, lid.height, lid.radius))\" fill=\"#FAF7EE\"/>"
let jarLayer = "<path d=\"\(shoulderedRect(body.x, body.y, body.width, body.height, top: body.top, bottom: body.bottom))\" "
    + "fill=\"#FAF7EE\"/>"

// A hand-built geometric P (no font outline): stem and bowl, centred on the jar's body.
let centreX = body.x + body.width / 2
let centreY = body.y + body.height / 2 + 20
let (stemWidth, bowlStroke, height, bowlHeight, bowlRadius) = (88.0, 70.0, 320.0, 216.0, 108.0)
let left = centreX - 108.0, top = centreY - height / 2, bottom = centreY + height / 2
let stemRight = left + stemWidth
let bowlRight = stemRight + 34.0
let outer = "M\(left),\(top) H\(bowlRight) A\(bowlRadius),\(bowlRadius) 0 0 1 \(bowlRight),\(top + bowlHeight) "
    + "H\(stemRight) V\(bottom) H\(left) Z"
let counterRadius = bowlRadius - bowlStroke
let counter = "M\(stemRight),\(top + bowlStroke) H\(bowlRight) "
    + "A\(counterRadius),\(counterRadius) 0 0 1 \(bowlRight),\(top + bowlHeight - bowlStroke) H\(stemRight) Z"
func letterPath(fill: String) -> String {
    "<path d=\"\(outer) \(counter)\" fill=\"\(fill)\" fill-rule=\"evenodd\"/>"
}

let letter = letterPath(fill: "#2F7A49")
/// The dark appearance's P sits on the garlic jar, not on the dark ground, so it keeps the deep green: the dark-mode
/// green (6DBE85) is 2.1:1 there (`AppIconBundleTests` asks for 3:1).
let letterDark = letterPath(fill: "#2F7A49")

try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try! svg(lidLayer).write(to: output.appendingPathComponent("lid.svg"), atomically: true, encoding: .utf8)
try! svg(jarLayer).write(to: output.appendingPathComponent("jar.svg"), atomically: true, encoding: .utf8)
try! svg(letter).write(to: output.appendingPathComponent("letter.svg"), atomically: true, encoding: .utf8)
try! svg(letterDark).write(to: output.appendingPathComponent("letter-dark.svg"), atomically: true, encoding: .utf8)
print("ok")
