// SPDX-License-Identifier: MIT
import XCTest

final class CollectionChipKeyboardReorderUITests: PestoUITestCase {
    private func createCollection(named name: String) -> XCUIElement {
        element(AccessibilityID.newCollectionButton).click()
        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitUntilExists(timeout: 5))
        app.typeText("\(name)\r")
        let chip = element(AccessibilityID.collectionChip(name))
        XCTAssertTrue(chip.waitUntilExists(timeout: 5), "collection \(name) was not created")
        return chip
    }

    func test_whenChoosingMoveLeftAndMoveRightInCollectionMenu_thenChipReorders() {
        launch()
        showOverlay()

        let alpha = createCollection(named: "Alpha")
        let beta = createCollection(named: "Beta")
        XCTAssertLessThan(alpha.frame.minX, beta.frame.minX, "Beta should start to the right of Alpha")

        beta.rightClick()
        let moveLeft = overlay.menuItems["Move Left"]
        XCTAssertTrue(moveLeft.waitUntilExists(timeout: 5), "Move Left menu item missing")
        moveLeft.click()

        let movedLeft = NSPredicate { _, _ in beta.frame.minX < alpha.frame.minX }
        wait(for: [XCTNSPredicateExpectation(predicate: movedLeft, object: nil)], timeout: 5)

        beta.rightClick()
        let moveRight = overlay.menuItems["Move Right"]
        XCTAssertTrue(moveRight.waitUntilExists(timeout: 5), "Move Right menu item missing")
        moveRight.click()

        let movedRight = NSPredicate { _, _ in beta.frame.minX > alpha.frame.minX }
        wait(for: [XCTNSPredicateExpectation(predicate: movedRight, object: nil)], timeout: 5)
    }
}
