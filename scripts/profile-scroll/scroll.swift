// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

guard AXIsProcessTrusted() else {
    print("NOT_TRUSTED")
    exit(2)
}

let screen = NSScreen.main!.frame
let point = CGPoint(x: screen.width / 2, y: screen.height - 110)
CGWarpMouseCursorPosition(point)
CGAssociateMouseAndMouseCursorPosition(1)
// A warp moves the cursor without an event, so the window server may still route scrolling to the window that was under
// it before. A real mouse-moved event first sends the scroll to the shelf.
if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
    move.post(tap: .cghidEventTap)
}

//// Pixel deltas with no gesture phases. Events marked continuous, with the scroll and momentum phases a trackpad
/// sends, were accepted and then ignored by the shelf (it never moved: `profile-scroll.sh` measured 16 points of
/// travel), while the same deltas without the phases scroll it, one 90 Hz step at a time.
func post(dx: Int32) {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0) else { return }
    e.location = point
    e.post(tap: .cghidEventTap)
}

let sweeps = Int(CommandLine.arguments.dropFirst().first ?? "6") ?? 6
Thread.sleep(forTimeInterval: 1.0)
for sweep in 0..<sweeps {
    let direction: Int32 = sweep % 2 == 0 ? -1 : 1
    for step in 0..<90 {
        let speed = Int32(40 + 30 * sin(Double(step) / 90 * .pi))
        post(dx: direction * speed)
        Thread.sleep(forTimeInterval: 1.0 / 90)
    }
    for step in 0..<30 {
        post(dx: direction * Int32(max(1, 30 - step)))
        Thread.sleep(forTimeInterval: 1.0 / 90)
    }
    Thread.sleep(forTimeInterval: 0.4)
}

print("DONE")
