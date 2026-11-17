// SPDX-License-Identifier: MIT
import XCTest

final class TopShelfUndoUITests: PestoUITestCase {
    func test_whenDeletingClipAndCollectionOnTopShelf_thenCommandZShowsUndoAndRestoresInPlace() {
        launch(defaults: ["hasOnboarded": "true", "shelfPosition": "top"])
        showOverlay()

        // Delete first clip and restore with ⌘Z
        let firstLabel = cards.firstMatch.label
        overlay.typeKey(.delete, modifierFlags: [])
        let confirm = element(AccessibilityID.deleteConfirmButton)
        XCTAssertTrue(confirm.waitUntilExists(timeout: 5))
        confirm.click()

        let deletedCard = cards.matching(NSPredicate(format: "label == %@", firstLabel)).firstMatch
        waitForNonExistence(deletedCard, timeout: 5, "clip should be removed after confirm")
        XCTAssertTrue(element(AccessibilityID.undoBanner).waitUntilExists(timeout: 5), "undo banner missing")

        overlay.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(deletedCard.waitUntilExists(timeout: 5), "⌘Z should restore deleted clip")
        XCTAssertEqual(cards.firstMatch.label, firstLabel, "restored clip should return in place")

        // Create and delete a collection, then restore with ⌘Z
        element(AccessibilityID.newCollectionButton).click()
        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitUntilExists(timeout: 5))
        app.typeText("TopWork\r")
        let chip = element(AccessibilityID.collectionChip("TopWork"))
        XCTAssertTrue(chip.waitUntilExists(timeout: 5))

        chip.rightClick()
        overlay.menuItems["Delete"].click()
        waitForNonExistence(chip, timeout: 5, "collection should be deleted")
        XCTAssertTrue(element(AccessibilityID.undoBanner).waitUntilExists(timeout: 5), "undo banner missing")

        overlay.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(chip.waitUntilExists(timeout: 5), "⌘Z should restore deleted collection")
    }
}
