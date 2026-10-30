// SPDX-License-Identifier: MIT
import XCTest

/// What a person does with a mouse on the shelf, with a real pointer: rest on a card to see its detail, click once to
/// pick it, sweep across the row. The timing rules are unit tested in Core (`HoverCardIntent`); these tests cover the
/// wiring (ADR 0009: a click only focuses, a double click pastes, the hover card is a window of its own).
final class PointerInteractionTests: PestoUITestCase {
    /// A synthesized pointer jump is sometimes not delivered as a hover to a window it re-enters; two small moves are.
    private func hover(_ card: XCUIElement) {
        let frame = card.frame
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        XCTAssertGreaterThan(frame.width, 0, "the card has no frame")
    }

    func test_restingThePointerOnACard_opensItsDetailAfterADwell_andLeavingClosesIt() {
        launch()
        showOverlay()
        XCTAssertFalse(element(AccessibilityID.cardDetailPopover).exists, "a detail is open before the pointer rests")

        hover(cards.element(boundBy: 1))

        XCTAssertTrue(
            element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 5),
            "resting the pointer on a card should open its detail"
        )
        capture("hover-detail-open")
        parkPointer()
        waitForNonExistence(
            element(AccessibilityID.cardDetailPopover), timeout: 5, "the detail stayed after the pointer left"
        )
    }

    func test_aSingleClick_onlyPicksACard_andNothingIsPasted() {
        launch()
        showOverlay()
        let target = cards.element(boundBy: 1)

        hover(target)
        target.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertTrue(pastedTexts().isEmpty, "a single click pasted: \(pastedTexts())")
        XCTAssertTrue(overlay.exists, "a single click closed the shelf")
        capture("single-click-picked")
    }

    func test_aFastSweepAcrossTheRow_leavesNoDetailOpenBehind() {
        launch()
        showOverlay()
        let count = min(cards.count, 5)
        XCTAssertGreaterThanOrEqual(count, 3, "the seed should give at least three cards")
        let frames = (0..<count).map { cards.element(boundBy: $0).frame }
        let y = frames[0].midY
        let origin = cards.element(boundBy: 0).coordinate(withNormalizedOffset: .zero)
        let startX = frames[0].minX

        for index in 0..<count {
            origin.withOffset(CGVector(dx: frames[index].midX - startX, dy: y - frames[0].minY)).hover()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        parkPointer()

        waitForNonExistence(
            element(AccessibilityID.cardDetailPopover), timeout: 5, "a detail was left open after a fast sweep"
        )
        XCTAssertTrue(overlay.exists, "the sweep closed the shelf")
    }
}
