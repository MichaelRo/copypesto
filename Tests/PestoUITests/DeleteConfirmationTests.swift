// SPDX-License-Identifier: MIT
import XCTest

/// The delete confirmation is drawn inside the shelf (`ShelfDeleteConfirmation`): a system alert in a non-activating
/// panel never became key, so Return did nothing until it was clicked. The shelf opens with its first card focused, so
/// Delete targets that card without a click (a click only moves focus now, a double click pastes).
final class DeleteConfirmationTests: PestoUITestCase {
    private var confirm: XCUIElement {
        element(AccessibilityID.deleteConfirmButton)
    }

    private var cancel: XCUIElement {
        element(AccessibilityID.deleteCancelButton)
    }

    func test_deletingThenPressingEscape_leavesTheClipInPlace() {
        launch()
        showOverlay()
        let label = cards.firstMatch.label

        overlay.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Delete should ask before removing the clip")

        overlay.typeKey(.escape, modifierFlags: [])

        waitForNonExistence(cancel, timeout: 5, "the question should close on Escape")
        XCTAssertTrue(overlay.exists, "Escape should cancel the question, not also close the shelf")
        XCTAssertTrue(
            cards.matching(NSPredicate(format: "label == %@", label)).firstMatch.waitForExistence(timeout: 5),
            "the clip should still be there after cancelling"
        )
    }

    /// The bug: Return did nothing until the alert was clicked with the trackpad.
    func test_deletingThenPressingReturn_removesTheClipWithoutAClick() {
        launch()
        showOverlay()
        let label = cards.firstMatch.label

        overlay.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete should ask before removing the clip")
        overlay.typeKey(.return, modifierFlags: [])

        waitForNonExistence(
            cards.matching(NSPredicate(format: "label == %@", label)).firstMatch, timeout: 5,
            "Return should confirm the delete"
        )
        XCTAssertTrue(pastedTexts().isEmpty, "Return on the question must not also paste the clip")
    }

    func test_deletingThenConfirmingWithTheButton_removesTheClip() {
        launch()
        showOverlay()
        let label = cards.firstMatch.label

        overlay.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete should ask before removing the clip")
        confirm.click()

        waitForNonExistence(
            cards.matching(NSPredicate(format: "label == %@", label)).firstMatch, timeout: 5,
            "confirming should remove the clip"
        )
    }

    /// Selects the first two cards with Space and the right arrow.
    private func selectFirstTwoCards() {
        overlay.typeKey(.space, modifierFlags: [])
        overlay.typeKey(.rightArrow, modifierFlags: [])
        overlay.typeKey(.space, modifierFlags: [])
    }

    func test_deletingSeveralSelectedClips_asksFirst_andCancelKeepsThem() {
        launch()
        showOverlay()
        let before = cards.count
        selectFirstTwoCards()

        element(AccessibilityID.deleteSelectedButton).click()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "deleting a selection should ask first")
        cancel.click()

        waitForNonExistence(cancel, timeout: 5, "the question should close")
        XCTAssertEqual(cards.count, before, "cancelling must keep every clip")
    }

    func test_deletingSeveralSelectedClips_removesThemOnlyOnceConfirmed() {
        launch()
        showOverlay()
        let before = cards.count
        selectFirstTwoCards()

        element(AccessibilityID.deleteSelectedButton).click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "deleting a selection should ask first")
        confirm.click()

        let removed = NSPredicate { _, _ in self.cards.count == before - 2 }
        wait(for: [XCTNSPredicateExpectation(predicate: removed, object: nil)], timeout: 8)
        XCTAssertEqual(cards.count, before - 2)
    }

    /// The bug: the Delete key removed one clip however many were selected.
    func test_deleteKeyWithASelection_removesTheWholeSelection() {
        launch()
        showOverlay()
        let before = cards.count
        selectFirstTwoCards()

        overlay.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete should ask before removing the selection")
        overlay.typeKey(.return, modifierFlags: [])

        let removed = NSPredicate { _, _ in self.cards.count == before - 2 }
        wait(for: [XCTNSPredicateExpectation(predicate: removed, object: nil)], timeout: 8)
        XCTAssertEqual(cards.count, before - 2, "the Delete key removed fewer clips than were selected")
    }
}
