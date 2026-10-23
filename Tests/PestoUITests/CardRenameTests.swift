// SPDX-License-Identifier: MIT
import XCTest

/// Rename is local state on the card, started from its context menu or from VoiceOver's action. The card hides its
/// children from accessibility, so the title field cannot be found as an element; the typing goes to whatever has the
/// keyboard focus, which is the field once Rename is chosen.
final class CardRenameTests: PestoUITestCase {
    private func startRename() {
        launch()
        showOverlay()
        let target = cards.firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.rightClick()
        app.menuItems["Rename\u{2026}"].click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    }

    private func cardsTitled(_ title: String) -> XCUIElementQuery {
        cards.matching(NSPredicate(format: "value CONTAINS %@", title))
    }

    func test_renamingFromTheContextMenu_showsTheTitleOnTheCard() {
        startRename()

        app.typeText("Quarterly figures\r")

        XCTAssertTrue(cardsTitled("Quarterly figures").firstMatch.waitForExistence(timeout: 5), "no new title")
        capture("card-renamed")
    }

    func test_escapeLeavesTheTitleAlone() {
        startRename()

        app.typeText("Never saved")
        app.typeKey(.escape, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        XCTAssertEqual(cardsTitled("Never saved").count, 0, "a title was saved that Escape should have dropped")
        XCTAssertTrue(overlay.exists, "Escape closed the shelf instead of only the title field")
    }

    func test_commandK_opensTheFocusedCardsMenu_andRenameWorksFromTheKeyboard() {
        launch()
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))

        app.typeKey("k", modifierFlags: .command)
        let rename = app.menuItems["Rename\u{2026}"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "⌘K did not open the card's menu")
        capture("card-actions-from-keyboard")
        rename.click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        app.typeText("From the keyboard\r")

        XCTAssertTrue(cardsTitled("From the keyboard").firstMatch.waitForExistence(timeout: 5), "no new title")
    }
}
