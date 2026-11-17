// SPDX-License-Identifier: MIT
import XCTest

final class FloatingWindowHoverUITests: PestoUITestCase {
    func test_whenHoveringScrollingAndLeavingFloatingWindow_thenDetailClosesWithoutFlicker() {
        launch()
        send(.togglePinnedWindow)

        let panel = element(AccessibilityID.pinnedPanel)
        XCTAssertTrue(panel.waitUntilExists(timeout: 10), "floating window did not appear")
        XCTAssertTrue(cards.firstMatch.waitUntilExists(timeout: 10), "no cards in floating window")

        let firstCard = cards.firstMatch
        XCTAssertTrue(firstCard.waitUntilExists(timeout: 5), "first card missing")
        firstCard.hover()

        let popover = element(AccessibilityID.cardDetailPopover)
        XCTAssertTrue(popover.waitUntilExists(timeout: 4), "hover detail did not open in floating window")

        panel.scroll(byDeltaX: -120, deltaY: 0)
        let outside = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(
            CGVector(dx: 0, dy: -120)
        )
        outside.hover()

        waitForNonExistence(popover, timeout: 3, "detail popover should close when pointer leaves")
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(popover.exists, "detail popover flickered back open on a neighbor")
    }
}
