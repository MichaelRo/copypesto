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

    /// Find bar 1b: the field opens in the command block's one row, so the panel and every card stay where they were.
    func test_openingFind_movesNoCard() {
        launch()
        showOverlay()
        let panelBefore = overlay.frame
        let cardBefore = cards.element(boundBy: 2).frame
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitUntilExists(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(overlay.frame.height, panelBefore.height, accuracy: 0.5, "the panel grew")
        XCTAssertEqual(cards.element(boundBy: 2).frame.minY, cardBefore.minY, accuracy: 0.5, "a card moved")
        let field = element(AccessibilityID.searchFieldFrame).frame
        XCTAssertGreaterThanOrEqual(field.width, 320, "the Find field is too narrow")
        XCTAssertEqual(field.midX, panelBefore.midX, accuracy: 120, "the Find field is far from the middle")
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

    /// A user's shelf showed the Undo offer after a delete cut in half by the panel's lower edge (2026-11-19): a banner
    /// above the command bar (Accessibility not granted here) took height the fixed panel did not have, and pushed
    /// everything under it down. Every card size, both resting places and a banner must keep the whole capsule inside
    /// the panel, on the screen and under the cards, and the cards where the height budget puts them.
    func test_undoOfferAfterADeleteIsWhollyInsideThePanel() {
        let setups: [(defaults: [String: String], accessibility: String)] = [
            ([:], "trusted"), (["cardSize": "compact"], "trusted"), (["cardSize": "large"], "trusted"),
            (["shelfPosition": "top"], "trusted"), (["cardSize": "compact", "shelfPosition": "top"], "trusted"),
            ([:], "denied"), (["shelfPosition": "top"], "denied"), ([:], "import")
        ]
        for (extra, accessibility) in setups {
            // "import" is the import offer's banner (another clipboard app's library found), with Accessibility
            // trusted.
            if accessibility == "import" {
                launch(defaults: ["hasOnboarded": "true"].merging(extra) { $1 }, importFixture: "maccy")
            } else {
                launch(accessibility: accessibility, defaults: ["hasOnboarded": "true"].merging(extra) { $1 })
            }
            showOverlay()
            overlay.typeKey(.delete, modifierFlags: [])
            let confirm = element(AccessibilityID.deleteConfirmButton)
            XCTAssertTrue(confirm.waitUntilExists(timeout: 5), "\(extra)")
            confirm.click()
            let banner = element(AccessibilityID.undoBanner)
            XCTAssertTrue(banner.waitUntilExists(timeout: 5), "undo offer missing \(extra)")
            let panel = overlay.frame
            let offer = banner.frame
            let screen = overlay.screenFrame
            XCTAssertGreaterThanOrEqual(offer.minY, panel.minY, "top edge inside the panel \(extra)")
            XCTAssertLessThanOrEqual(offer.maxY, panel.maxY - 2, "bottom edge inside the panel \(extra)")
            XCTAssertLessThanOrEqual(
                offer.maxY, screen.maxY,
                "bottom edge on the screen \(extra) \(accessibility) panel \(panel) offer \(offer) screen \(screen) "
                    + "window \(app.windows.matching(identifier: AccessibilityID.overlayPanel).firstMatch.frame)"
            )
            let card = cards.firstMatch.frame
            XCTAssertGreaterThanOrEqual(offer.minY - card.maxY, 0, "the offer covers no card \(extra)")
            XCTAssertEqual(
                panel.maxY - card.maxY,
                46,
                accuracy: 1.5,
                "the band under the cards \(extra) \(accessibility)"
            )
            app.terminate()
        }
    }
}

private extension XCUIElement {
    /// The frame of the display this element is on, in XCUITest's top-left coordinates. `NSScreen` frames are
    /// bottom-left based from the main display's corner; the shelf opens on the display of the frontmost app, which on
    /// a Mac with two displays is not always the main one.
    var screenFrame: CGRect {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return .infinite }
        let displays = NSScreen.screens.map { screen in
            CGRect(
                x: screen.frame.minX, y: mainHeight - screen.frame.maxY,
                width: screen.frame.width, height: screen.frame.height
            )
        }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.contains(centre) } ?? .infinite
    }
}
