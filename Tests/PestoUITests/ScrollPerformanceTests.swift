// SPDX-License-Identifier: MIT
import XCTest

/// The shelf's own budget is a smooth horizontal scroll over a long history. This drives wheel scrolling across cards
/// that have not been drawn yet, so every step pays the cost of cards appearing, and records the app's CPU time and
/// the wall-clock time of the whole sweep. Lower is better; there is no stored baseline, read the numbers in the log.
final class ScrollPerformanceTests: PestoUITestCase {
    func test_scrollingAcrossNewCards_costsLittle() {
        launch(seed: "large", timeout: 300)
        showOverlay()
        let sweep = {
            for _ in 0..<12 {
                self.overlay.scroll(byDeltaX: -600, deltaY: 0)
            }
            for _ in 0..<12 {
                self.overlay.scroll(byDeltaX: 600, deltaY: 0)
            }
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options) {
            sweep()
        }

        XCTAssertGreaterThan(cards.count, 0, "the grid went blank while scrolling")
    }

    func test_arrowKeys_scrollTheFocusedCardIntoViewFarAlongTheShelf() {
        launch(seed: "large", timeout: 300)
        showOverlay()

        for _ in 0..<40 {
            overlay.typeKey(.rightArrow, modifierFlags: [])
        }

        let focused = card(containing: "Clip #4959")
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "the card 40 steps along was never drawn")
        XCTAssertTrue(focused.isHittable, "the focused card should have been scrolled into view")
    }

    /// A clip copied while the shelf was closed (from an iPhone, say) is the newest and must be what the shelf shows
    /// when it opens: the shelf used to scroll to the clip that was first before it, leaving the new one off screen.
    func test_reopening_afterACopyMadeWhileClosed_startsAtTheNewestClip() {
        launch(seed: "large", timeout: 300)
        showOverlay()
        for _ in 0..<40 {
            overlay.typeKey(.rightArrow, modifierFlags: [])
        }
        overlay.typeKey(.escape, modifierFlags: [])
        waitForNonExistence(overlay, timeout: 5, "the shelf should close")
        let sentinel = "pesto-newest-\(UUID().uuidString.prefix(6))"
        copyToClipboard(sentinel)
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        showOverlay()

        let newest = card(containing: sentinel)
        XCTAssertTrue(newest.waitForExistence(timeout: 5), "the clip copied while closed is not on the shelf")
        XCTAssertTrue(newest.isHittable, "the shelf opened scrolled past the newest clip")
        XCTAssertLessThan(newest.frame.minX - overlay.frame.minX, 40, "the newest clip is not at the start")
    }
}
