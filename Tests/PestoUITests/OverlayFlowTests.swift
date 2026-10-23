// SPDX-License-Identifier: MIT
import XCTest

final class OverlayFlowTests: PestoUITestCase {
    func test_whenOverlayCommandSent_thenSeededCardsAppear() {
        launch()
        showOverlay()

        XCTAssertGreaterThanOrEqual(cards.count, 4)
        XCTAssertTrue(card(containing: "Quarterly report draft").exists, "newest seeded item should be first")
        capture("overlay-open")
    }

    /// The first card is focused on open and scrolled to the start; it must keep the same margin it has when the shelf
    /// is scrolled back by hand, not sit flush against the screen edge.
    func test_firstCard_keepsTheShelfMarginWhenFocusedOnOpen() {
        launch()
        showOverlay()
        let first = cards.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))

        let margin = first.frame.minX - overlay.frame.minX

        XCTAssertGreaterThanOrEqual(margin, 14, "the first card sits against the left edge (margin \(margin) pt)")
        XCTAssertLessThanOrEqual(margin, 20)
    }

    func test_escape_dismissesOverlayWithoutPasting() {
        launch()
        showOverlay()

        overlay.typeKey(.escape, modifierFlags: [])

        waitForNonExistence(overlay, timeout: 5, "overlay should dismiss on Escape")
        XCTAssertEqual(pastedTexts(), [], "Escape must not paste")
    }

    /// A single click only moves focus (ADR 0009): the shelf stays open and Return then pastes that card.
    func test_singleClick_focusesTheCardWithoutPasting() {
        launch()
        showOverlay()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let target = card(containing: "Quarterly report draft")

        target.click()

        XCTAssertTrue(overlay.waitForExistence(timeout: 2), "a single click must not paste or close the shelf")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(pastedTexts().isEmpty, "nothing was pasted by a single click")
        overlay.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(waitForPaste(count: 1), ["Quarterly report draft — final review pending."])
    }

    func test_selectCard_pastesItsPayloadAndDismisses() {
        launch()
        showOverlay()
        // Hovering a card shows its hover card after a short delay; the click must still land.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let expected = "Quarterly report draft — final review pending."
        let target = card(containing: "Quarterly report draft")
        capture("before-select")

        target.hover()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        capture("popover-open")
        target.doubleClick()

        XCTAssertEqual(waitForPaste(count: 1), [expected])
        waitForNonExistence(overlay, timeout: 5, "overlay should dismiss after selecting a card")
    }

    func test_sensitiveCards_neverExposeTheSecretToAccessibility() {
        launch()
        showOverlay()

        let labels = (0..<cards.count).map { cards.element(boundBy: $0).label }

        XCTAssertFalse(labels.contains { $0.contains("4242 4242 4242 4242") }, "card number leaked: \(labels)")
        XCTAssertFalse(labels.contains { $0.contains("EXAMPLEEXAMPLE") }, "API key leaked: \(labels)")
    }

    func test_copyWhileRunning_addsACardAtTheFront() {
        launch()
        let sentinel = "pesto-uitest-copy-\(UUID().uuidString.prefix(6))"

        copyToClipboard(sentinel)
        showOverlay()

        XCTAssertTrue(card(containing: sentinel).waitForExistence(timeout: 10), "copied text never appeared")
        capture("after-copy")
    }
}
