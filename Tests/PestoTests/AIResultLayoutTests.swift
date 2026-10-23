// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import Pesto

@Suite("AI answer height")
struct AIResultLayoutTests {
    private var width: CGFloat {
        AIResultLayout.textWidth
    }

    @Test("a longer answer gets a taller area, up to a cap past which it scrolls")
    func heightFollowsTheText() {
        let short = AIResultLayout.answerHeight(for: "Short.", width: width)
        let medium = AIResultLayout.answerHeight(
            for: String(repeating: "The sequence of numbers appears to be random. ", count: 4),
            width: width
        )
        let huge = AIResultLayout.answerHeight(for: String(repeating: "A long sentence. ", count: 400), width: width)

        #expect(short < medium, "short \(short) medium \(medium) huge \(huge)")
        #expect(medium < huge)
        #expect(huge == AIResultLayout.maximumHeight)
        #expect(short >= AIResultLayout.minimumHeight)
    }

    @Test("two lines of answer are not squeezed into one line's room")
    func twoLinesFit() {
        let two = AIResultLayout.answerHeight(
            for: "The sequence of numbers appears to be random. No discernible pattern or meaning is evident.",
            width: width
        )
        #expect(two >= 90, "a two-line answer needs room for both lines: \(two)")
    }

    @Test("the panel stops at 520 points, or at 60 percent of the display's visible height on a small one")
    func panelHeightCap() {
        #expect(AIResultLayout.panelCap(visibleHeight: 1400, readsInParts: false) == 520)
        #expect(AIResultLayout.panelCap(visibleHeight: 800, readsInParts: false) == 480)
        #expect(AIResultLayout.panelCap(visibleHeight: 400, readsInParts: false) == 240)
        #expect(AIResultLayout.panelCap(visibleHeight: 1400, readsInParts: true) == 560)
    }

    @Test("a tiny display never shrinks the panel below what its header and buttons need")
    func panelCapHasAFloor() {
        #expect(AIResultLayout.panelCap(visibleHeight: 200, readsInParts: false) >= 220)
    }
}
