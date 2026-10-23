// SPDX-License-Identifier: MIT
import AppKit

/// Generates the vector layers for Pesto.icon: run `swift design/source/icon-layers.swift <output dir>`.
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func roundedRect(_ x: Double, _ y: Double, _ size: Double, _ radius: Double) -> String {
    let r = radius
    let (l, t, rr, b) = (x, y, x + size, y + size)
    return "M\(l + r),\(t) H\(rr - r) A\(r),\(r) 0 0 1 \(rr),\(t + r) V\(b - r) A\(r),\(r) 0 0 1 \(rr - r),\(b) "
        + "H\(l + r) A\(r),\(r) 0 0 1 \(l),\(b - r) V\(t + r) A\(r),\(r) 0 0 1 \(l + r),\(t) Z"
}

func svg(_ body: String) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\(body)</svg>\n"
}

let card = 540.0, radius = 150.0, step = 80.0
let origin = (1024 - (card + 2 * step)) / 2
let cards = [
    (origin + 2 * step, 0.34), // back
    (origin + step, 0.5)
]
var cardBody = ""
for (offset, opacity) in cards {
    cardBody += "<path d=\"\(roundedRect(offset, offset, card, radius))\" fill=\"#F6EFD9\" fill-opacity=\"\(opacity)\"/>"
}

let frontCard = "<path d=\"\(roundedRect(origin, origin, card, radius))\" fill=\"#FAF7EE\" fill-opacity=\"1\"/>"

// A hand-built geometric P (no font outline): stem and bowl, centred on the front card.
let centre = origin + card / 2
let (stemWidth, bowlStroke, height, bowlHeight, bowlRadius) = (88.0, 70.0, 320.0, 216.0, 108.0)
let left = centre - 108.0, top = centre - height / 2, bottom = centre + height / 2
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
/// The dark appearance's P sits on the garlic front card, not on the dark ground, so it keeps the deep green: the
/// dark-mode green (6DBE85) is 2.1:1 there (`AppIconBundleTests` asks for 3:1).
let letterDark = letterPath(fill: "#2F7A49")

try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try! svg(cardBody).write(to: output.appendingPathComponent("stack.svg"), atomically: true, encoding: .utf8)
try! svg(frontCard).write(to: output.appendingPathComponent("front-card.svg"), atomically: true, encoding: .utf8)
try! svg(letter).write(to: output.appendingPathComponent("letter.svg"), atomically: true, encoding: .utf8)
try! svg(letterDark).write(to: output.appendingPathComponent("letter-dark.svg"), atomically: true, encoding: .utf8)
print("ok")
