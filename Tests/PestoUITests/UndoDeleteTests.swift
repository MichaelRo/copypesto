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
        XCTAssertTrue(undo.waitUntilExists(timeout: 5), "a delete should offer Undo")
        capture("undo-banner")
        undo.click()

        XCTAssertTrue(
            cards.matching(NSPredicate(format: "label == %@", label)).firstMatch.waitUntilExists(timeout: 5),
            "Undo should bring the clip back"
        )
        waitForNonExistence(undo, timeout: 5, "the banner should go once it is used")
    }

    func test_theUndoBanner_doesNotMoveTheToolbar() {
        launch()
        showOverlay()
        let search = element(AccessibilityID.searchButton)
        XCTAssertTrue(search.waitUntilExists(timeout: 5))
        let before = search.frame

        _ = deleteFirstCard()

        XCTAssertTrue(element(AccessibilityID.undoButton).waitUntilExists(timeout: 5))
        XCTAssertEqual(search.frame.minY, before.minY, accuracy: 1, "the Undo banner pushed the toolbar down (D-03)")
    }

    func test_commandZThenShiftCommandZ_undoesAndRedoesTheDelete() {
        launch()
        showOverlay()
        let label = deleteFirstCard()
        let card = cards.matching(NSPredicate(format: "label == %@", label)).firstMatch

        overlay.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(card.waitUntilExists(timeout: 5), "⌘Z should bring the clip back")

        overlay.typeKey("z", modifierFlags: [.command, .shift])
        waitForNonExistence(card, timeout: 5, "⇧⌘Z should delete it again")
    }

    private func createCollection(named name: String) -> XCUIElement {
        element(AccessibilityID.newCollectionButton).click()
        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitUntilExists(timeout: 5))
        app.typeText("\(name)\r")
        let chip = element(AccessibilityID.collectionChip(name))
        XCTAssertTrue(chip.waitUntilExists(timeout: 5), "the collection \(name) was not created")
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
        XCTAssertTrue(undo.waitUntilExists(timeout: 5), "deleting a collection should offer Undo")
        undo.click()
        XCTAssertTrue(chip.waitUntilExists(timeout: 5), "Undo should bring the collection back")
    }

    func test_commandZ_takesBackANewCollection() {
        launch()
        showOverlay()
        let chip = createCollection(named: "Work")

        overlay.typeKey("z", modifierFlags: .command)
        waitForNonExistence(chip, timeout: 5, "⌘Z should take the new collection back")

        overlay.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(chip.waitUntilExists(timeout: 5), "⇧⌘Z should add it again")
    }

    func test_whenHiddenNSFWClipsAreShownSelectedAllAndDeleted_thenCommandZBringsThemBack() {
        launch(seed: "empty", defaults: ["hasOnboarded": "true", "nsfwMode": "hide"])
        copyToClipboard("https://erome.com/clip.gif")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        copyToClipboard("https://erome.com/album/1")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        showOverlay(expectingCards: false)
        element(AccessibilityID.searchButton).click()
        let hiddenChip = element(AccessibilityID.filterChip("Hidden"))
        XCTAssertTrue(hiddenChip.waitUntilExists(timeout: 5), "Hidden filter chip should appear in Search")
        hiddenChip.click()
        XCTAssertTrue(cards.firstMatch.waitUntilExists(timeout: 5), "Hidden NSFW clips should appear")
        XCTAssertEqual(cards.count, 2)

        overlay.typeKey("a", modifierFlags: .command)
        let deleteSelected = element(AccessibilityID.deleteSelectedButton)
        XCTAssertTrue(deleteSelected.waitUntilExists(timeout: 5), "Selection action bar should appear")
        deleteSelected.click()
        XCTAssertTrue(element(AccessibilityID.deleteConfirmButton).waitUntilExists(timeout: 5))
        element(AccessibilityID.deleteConfirmButton).click()
        waitForNonExistence(cards.firstMatch, timeout: 5, "Deleting all hidden clips should clear the grid")

        overlay.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(cards.firstMatch.waitUntilExists(timeout: 5), "⌘Z should restore the deleted NSFW clips")
        XCTAssertEqual(cards.count, 2)
    }
}
