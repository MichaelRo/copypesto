// SPDX-License-Identifier: MIT
import Testing
@testable import Pesto

@Suite("The card-size slider speaks its value")
@MainActor
struct TickSliderSpokenValueTests {
    private let names: [Double: String] = [160: "Compact", 190: "Standard", 240: "Large"]

    @Test("on a named tick the value says what the tick is")
    func whenOnATick_thenTheNameFollows() {
        #expect(TickSlider.spokenValue(190, tickNames: names, tolerance: 6) == "190 points, Standard")
        #expect(TickSlider.spokenValue(193, tickNames: names, tolerance: 6) == "193 points, Standard")
    }

    @Test("between ticks it says only the number")
    func whenBetween_thenNumberOnly() {
        #expect(TickSlider.spokenValue(215, tickNames: names, tolerance: 6) == "215 points")
    }

    @Test("a tick with no name adds nothing")
    func whenUnnamed_thenNumberOnly() {
        #expect(TickSlider.spokenValue(100, tickNames: [100: ""], tolerance: 6) == "100 points")
    }
}
