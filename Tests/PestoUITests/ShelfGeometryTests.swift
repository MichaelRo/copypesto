// SPDX-License-Identifier: MIT
import XCTest

/// The panel's height is fixed (`ShelfHeight`), so where the cards sit in it is a budget: the command bar above, the
/// lift room around the row and the slot under it. These measure the real shelf, so a padding that is added twice
/// shows as a number and not as a clipped bar.
final class ShelfGeometryTests: PestoUITestCase {
    func test_cardsSitWhereTheHeightBudgetPutsThem() {
        launch()
        showOverlay()
        let panel = overlay.frame
        let card = cards.element(boundBy: 3).frame
        XCTAssertEqual(panel.height - card.height, 112, accuracy: 1.5, "ShelfHeight.chrome")
        XCTAssertEqual(card.minY - panel.minY, 66, accuracy: 1.5, "command bar block plus half the lift room")
        XCTAssertEqual(panel.maxY - card.maxY, 46, accuracy: 1.5, "half the lift room plus the bottom slot")
    }

    func test_selectionBarRestsInsideTheBandUnderTheCards() {
        launch()
        showOverlay()
        overlay.typeKey("a", modifierFlags: .command)
        let button = element(AccessibilityID.deleteSelectedButton)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let panel = overlay.frame
        let card = cards.element(boundBy: 3).frame
        XCTAssertEqual(panel.maxY - button.frame.maxY, 11, accuracy: 1.5, "8 pt under the capsule and its 3 pt rim")
        XCTAssertGreaterThanOrEqual(button.frame.minY - card.maxY, 8, "the capsule must clear the row")
    }
}
