// SPDX-License-Identifier: MIT
import XCTest

final class SensitiveCardTests: PestoUITestCase {
    /// Automatic detection can miss things, so any card can be marked by hand.
    func test_markingACardAsSensitive_blursItAndCanBeUndone() {
        launch()
        showOverlay()
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.rightClick()
        app.menuItems["Mark as Sensitive"].click()
        let hidden = cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'")).firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 5), "the card was not blurred")
        XCTAssertEqual(cardCount(containing: "Quarterly report draft"), 0, "the blurred card must not expose its text")
        capture("card-marked-sensitive")

        hidden.rightClick()
        app.menuItems["Mark as Not Sensitive"].click()
        XCTAssertTrue(
            card(containing: "Quarterly report draft").waitForExistence(timeout: 5),
            "the card did not come back"
        )
    }

    /// A hidden card is read with Show: Quick Look, the AI actions and Describe Image would show what the blur hides.
    func test_blurredCard_offersShowButNotQuickLookOrAIActions() {
        launch()
        showOverlay()
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.rightClick()
        XCTAssertTrue(app.menuItems["Quick Look"].waitForExistence(timeout: 5), "an ordinary card offers Quick Look")
        app.menuItems["Mark as Sensitive"].click()
        let hidden = cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'")).firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 5))

        hidden.rightClick()

        XCTAssertTrue(app.menuItems["Show"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["Quick Look"].exists, "Quick Look would show the clip without Show")
        // "Summarize" and "Translate" are also macOS's own Writing Tools and Services items; "Extract" is only Pesto's.
        XCTAssertFalse(app.menuItems["Extract"].exists, "an AI answer would repeat what is hidden")
        XCTAssertFalse(app.menuItems["AI Actions"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    /// After revealing a flagged card the menu offers to hide it again without un-marking it.
    func test_revealedSensitiveCard_canBeHiddenAgain() {
        launch()
        showOverlay()
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.rightClick()
        app.menuItems["Mark as Sensitive"].click()
        let hiddenQuery = cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'"))
        XCTAssertTrue(hiddenQuery.firstMatch.waitForExistence(timeout: 5))

        hiddenQuery.firstMatch.rightClick()
        app.menuItems["Show"].click()
        XCTAssertTrue(
            card(containing: "Quarterly report draft").waitForExistence(timeout: 5),
            "Show should reveal it"
        )
        card(containing: "Quarterly report draft").rightClick()
        XCTAssertTrue(app.menuItems["Mark as Not Sensitive"].waitForExistence(timeout: 5))
        app.menuItems["Hide Again"].click()

        XCTAssertTrue(hiddenQuery.firstMatch.waitForExistence(timeout: 5), "Hide Again should blur the card again")
    }
}

final class SensitiveCardKeyboardTests: PestoUITestCase {
    private func markFirstCardSensitive() -> XCUIElement {
        launch()
        showOverlay()
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.rightClick()
        app.menuItems["Mark as Sensitive"].click()
        let hidden = cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'")).firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 5))
        return hidden
    }

    /// A hidden card could only be shown with a mouse. ADR 0003: showing is always deliberate; Return
    /// pastes.
    func test_showFromTheMenu_revealsAHiddenCard() {
        let hidden = markFirstCardSensitive()

        hidden.rightClick()
        app.menuItems["Show"].click()

        XCTAssertTrue(
            card(containing: "Quarterly report draft").waitForExistence(timeout: 5),
            "Show should reveal the card"
        )
    }

    /// The brief had no direct key for Show: ⌘K and arrow to Show worked, but ⌘Return does it in one press.
    func test_commandReturnOnAHiddenCard_showsIt_andAgainHidesIt() {
        _ = markFirstCardSensitive()
        parkPointer()

        overlay.typeKey(.return, modifierFlags: .command)

        XCTAssertTrue(
            card(containing: "Quarterly report draft").waitForExistence(timeout: 5),
            "⌘Return should show the focused hidden card"
        )
        XCTAssertTrue(overlay.exists, "⌘Return must show the card, not paste it and close the shelf")

        overlay.typeKey(.return, modifierFlags: .command)

        XCTAssertTrue(
            cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'")).firstMatch
                .waitForExistence(timeout: 5),
            "⌘Return on a shown card should hide it again"
        )
    }

    func test_returnOnAHiddenCard_pastesItWithoutShowingIt() {
        _ = markFirstCardSensitive()
        parkPointer()

        overlay.typeKey(.return, modifierFlags: [])

        waitForNonExistence(overlay, timeout: 5, "Return on a hidden card should paste it and close the shelf")
    }

    func test_doubleClickOnAHiddenCard_pastesItWithoutShowingIt() {
        let hidden = markFirstCardSensitive()

        hidden.doubleClick()

        waitForNonExistence(overlay, timeout: 5, "a double click on a hidden card should paste it and close the shelf")
    }

    func test_showButtonOnAHiddenCard_revealsItWithoutPasting() {
        let hidden = markFirstCardSensitive()

        // The card is one accessibility element, so its Show button is clicked where it is drawn.
        hidden.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).click()

        XCTAssertTrue(
            card(containing: "Quarterly report draft").waitForExistence(timeout: 5),
            "the Show button should reveal the card"
        )
        XCTAssertTrue(overlay.exists, "showing a card must not paste it")
    }
}
