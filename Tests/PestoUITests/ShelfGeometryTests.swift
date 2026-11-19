// SPDX-License-Identifier: MIT
import AppKit
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
        XCTAssertTrue(button.waitUntilExists(timeout: 5))
        let panel = overlay.frame
        let card = cards.element(boundBy: 3).frame
        XCTAssertEqual(panel.maxY - button.frame.maxY, 11, accuracy: 1.5, "8 pt under the capsule and its 3 pt rim")
        XCTAssertGreaterThanOrEqual(button.frame.minY - card.maxY, 8, "the capsule must clear the row")
    }

    /// A user's shelf showed the Undo offer after a delete cut in half by the panel's lower edge (2026-11-19). Every
    /// card size and both resting places must keep the whole capsule inside the panel and on the screen.
    func test_undoOfferAfterADeleteIsWhollyInsideThePanel() {
        let setups: [[String: String]] = [
            [:], ["cardSize": "compact"], ["cardSize": "large"], ["shelfPosition": "top"],
            ["cardSize": "compact", "shelfPosition": "top"]
        ]
        for extra in setups {
            launch(defaults: ["hasOnboarded": "true"].merging(extra) { $1 })
            showOverlay()
            overlay.typeKey(.delete, modifierFlags: [])
            let confirm = element(AccessibilityID.deleteConfirmButton)
            XCTAssertTrue(confirm.waitUntilExists(timeout: 5), "\(extra)")
            confirm.click()
            let banner = element(AccessibilityID.undoBanner)
            XCTAssertTrue(banner.waitUntilExists(timeout: 5), "undo offer missing \(extra)")
            let panel = overlay.frame
            let offer = banner.frame
            let screen = app.windows.firstMatch.screenFrame
            XCTAssertGreaterThanOrEqual(offer.minY, panel.minY, "top edge inside the panel \(extra)")
            XCTAssertLessThanOrEqual(offer.maxY, panel.maxY - 2, "bottom edge inside the panel \(extra)")
            XCTAssertLessThanOrEqual(offer.maxY, screen.maxY, "bottom edge on the screen \(extra)")
            let card = cards.firstMatch.frame
            XCTAssertGreaterThanOrEqual(offer.minY - card.maxY, 0, "the offer covers no card \(extra)")
            app.terminate()
        }
    }
}

private extension XCUIElement {
    /// The main display's frame. XCUITest frames are top-left based and `NSScreen` frames bottom-left based, but for
    /// the main display (origin 0, 0) the height is the bottom edge in both.
    var screenFrame: CGRect {
        NSScreen.screens.first?.frame ?? .infinite
    }
}
