// SPDX-License-Identifier: MIT
import XCTest

/// The detail popover opened only on a 400 ms mouse hover, so a keyboard-only or
/// VoiceOver user who moved focus onto a card never saw it.
final class CardDetailPopoverTests: PestoUITestCase {
    func test_movingKeyboardFocusToACard_opensTheDetailPopoverAfterADelay() {
        launch()
        showOverlay()

        overlay.typeKey(.rightArrow, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        XCTAssertTrue(
            element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 2),
            "keyboard focus on a card should open its detail popover, same as hover does"
        )
    }

    /// Plain text used to open a popover with nothing in it but the app and the date.
    func test_focusingAPlainTextCard_showsItsText() {
        launch()
        showOverlay()
        overlay.typeKey(.rightArrow, modifierFlags: [])
        overlay.typeKey(.leftArrow, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let popover = element(AccessibilityID.cardDetailPopover)
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "keyboard focus on a card should open its popover")
        let text = popover.staticTexts.matching(NSPredicate(
            format: "value CONTAINS 'final review pending' OR label CONTAINS 'final review pending'"
        )).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "the popover of a plain text clip should show the text")
    }

    func test_openingTheShelf_doesNotShowADetailPopoverUntilTheUserActs() {
        launch()
        showOverlay()

        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        XCTAssertFalse(
            element(AccessibilityID.cardDetailPopover).exists,
            "an idle shelf must not pin a detail popover on its first card"
        )
    }

    func test_aKeyboardRevealedPopover_staysWhileFocusStaysOnTheCard() {
        launch()
        showOverlay()
        overlay.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 3))

        RunLoop.current.run(until: Date().addingTimeInterval(7))

        XCTAssertTrue(
            element(AccessibilityID.cardDetailPopover).exists,
            "a revealed card lasts as long as the focus does, not a few seconds"
        )
    }

    func test_theFirstEscape_closesOnlyTheHoverCard() {
        launch()
        showOverlay()
        overlay.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 3))

        overlay.typeKey(.escape, modifierFlags: [])

        waitForNonExistence(element(AccessibilityID.cardDetailPopover), timeout: 3, "Esc should close the card")
        XCTAssertTrue(overlay.exists, "the first Escape must leave the shelf open")
    }

    func test_hoveringAnotherCard_replacesTheHoverCard() {
        launch()
        showOverlay()
        parkPointer()
        let first = cards.element(boundBy: 0)
        let second = cards.element(boundBy: 1)
        first.hover()
        if !element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 2) {
            second.hover()
            first.hover()
        }
        XCTAssertTrue(element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 4))

        second.hover()
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let hoverCardWindows = app.windows.matching(NSPredicate(format: "label == 'Clip details'"))
        XCTAssertEqual(hoverCardWindows.count, 1, "only one hover card window is ever open")
        XCTAssertTrue(element(AccessibilityID.cardDetailPopover).exists)
    }

    func test_openingTheContextMenu_hidesTheDetailPopover() {
        launch()
        showOverlay()
        let card = cards.firstMatch
        parkPointer()
        card.hover()
        if !element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 2) {
            cards.element(boundBy: 1).hover()
            card.hover()
        }
        XCTAssertTrue(element(AccessibilityID.cardDetailPopover).waitForExistence(timeout: 4))

        card.rightClick()

        XCTAssertTrue(app.menuItems["Quick Look"].waitForExistence(timeout: 5))
        waitForNonExistence(
            element(AccessibilityID.cardDetailPopover),
            timeout: 3,
            "the menu should replace the popover"
        )
    }
}
