// SPDX-License-Identifier: MIT
import XCTest

/// ADR 0008: a delete from the shelf offers Undo, and ⌘Z and ⇧⌘Z take it back and do it again.
final class UndoDeleteTests: PestoUITestCase {
    private func deleteFirstCard() -> String {
        let label = cards.firstMatch.label
        overlay.typeKey(.delete, modifierFlags: [])
        element(AccessibilityID.deleteConfirmButton).click()
        waitForNonExistence(
            cards.matching(NSPredicate(format: "label == %@", label)).firstMatch, timeout: 5,
            "confirming should remove the clip"
        )
        return label
    }

    func test_afterADelete_theUndoButtonBringsTheClipBack() {
        launch()
        showOverlay()
        let label = deleteFirstCard()

        let undo = element(AccessibilityID.undoButton)
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "a delete should offer Undo")
        capture("undo-banner")
        undo.click()

        XCTAssertTrue(
            cards.matching(NSPredicate(format: "label == %@", label)).firstMatch.waitForExistence(timeout: 5),
            "Undo should bring the clip back"
        )
        waitForNonExistence(undo, timeout: 5, "the banner should go once it is used")
    }

    func test_theUndoBanner_doesNotMoveTheToolbar() {
        launch()
        showOverlay()
        let search = element(AccessibilityID.searchButton)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let before = search.frame

        _ = deleteFirstCard()

        XCTAssertTrue(element(AccessibilityID.undoButton).waitForExistence(timeout: 5))
        XCTAssertEqual(search.frame.minY, before.minY, accuracy: 1, "the Undo banner pushed the toolbar down (D-03)")
    }

    func test_commandZThenShiftCommandZ_undoesAndRedoesTheDelete() {
        launch()
        showOverlay()
        let label = deleteFirstCard()
        let card = cards.matching(NSPredicate(format: "label == %@", label)).firstMatch

        overlay.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "⌘Z should bring the clip back")

        overlay.typeKey("z", modifierFlags: [.command, .shift])
        waitForNonExistence(card, timeout: 5, "⇧⌘Z should delete it again")
    }

    private func createCollection(named name: String) -> XCUIElement {
        element(AccessibilityID.newCollectionButton).click()
        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 5))
        app.typeText("\(name)\r")
        let chip = element(AccessibilityID.collectionChip(name))
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the collection \(name) was not created")
        return chip
    }

    func test_afterDeletingACollection_undoBringsItBack() {
        launch()
        showOverlay()
        let chip = createCollection(named: "Work")

        chip.rightClick()
        overlay.menuItems["Delete"].click()
        waitForNonExistence(chip, timeout: 5, "the collection should be deleted")

        let undo = element(AccessibilityID.undoButton)
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "deleting a collection should offer Undo")
        undo.click()
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "Undo should bring the collection back")
    }

    func test_commandZ_takesBackANewCollection() {
        launch()
        showOverlay()
        let chip = createCollection(named: "Work")

        overlay.typeKey("z", modifierFlags: .command)
        waitForNonExistence(chip, timeout: 5, "⌘Z should take the new collection back")

        overlay.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "⇧⌘Z should add it again")
    }
}
