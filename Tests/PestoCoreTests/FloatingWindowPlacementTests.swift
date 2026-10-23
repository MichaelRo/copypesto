// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Where the floating window opens")
struct FloatingWindowPlacementTests {
    private let main = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let side = CGRect(x: 1512, y: 100, width: 1920, height: 1040)

    @Test("a frame saved on the display being worked in stays where it is")
    func whenOnTheTargetDisplay_thenUnchanged() {
        let saved = CGRect(x: 300, y: 60, width: 900, height: 320)
        #expect(FloatingWindowPlacement.frame(saved: saved, displays: [main, side], target: main) == saved)
    }

    @Test("a frame saved on the other display moves across with the same offset from its corner")
    func whenOnAnotherDisplay_thenMovesToTheTarget() {
        let saved = CGRect(x: 1812, y: 160, width: 900, height: 320)
        let frame = FloatingWindowPlacement.frame(saved: saved, displays: [main, side], target: main)
        #expect(frame == CGRect(x: 300, y: 60, width: 900, height: 320))
    }

    @Test("it is cut to fit a smaller display, and a frame on no display lands inside the target")
    func whenTooBigOrLost_thenFitsTheTarget() {
        let big = CGRect(x: 1612, y: 100, width: 1800, height: 1000)
        let frame = FloatingWindowPlacement.frame(saved: big, displays: [main, side], target: main)
        #expect(main.contains(frame))
        let lost = CGRect(x: 9000, y: 9000, width: 900, height: 320)
        #expect(main.contains(FloatingWindowPlacement.frame(saved: lost, displays: [main, side], target: main)))
    }

    @Test("a frame that grew past an edge is moved back inside, keeping its size")
    func whenPastAnEdge_thenFitMovesItBack() {
        let frame = CGRect(x: 600, y: -300, width: 340, height: 480)
        #expect(FloatingWindowPlacement.fit(frame, in: main) == CGRect(x: 600, y: 0, width: 340, height: 480))
        let top = CGRect(x: 600, y: 700, width: 340, height: 480)
        #expect(FloatingWindowPlacement.fit(top, in: main).maxY == main.maxY)
    }
}
