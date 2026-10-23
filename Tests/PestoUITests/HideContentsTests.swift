// SPDX-License-Identifier: MIT
import XCTest

final class HideContentsTests: PestoUITestCase {
    func test_hideClipContents_coversTheCardsAndShowBringsThemBack() {
        launch()
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        capture("cards-shown")

        send(.toggleHideContents)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("cards-hidden-for-sharing")

        send(.toggleHideContents)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(cards.firstMatch.exists)
        capture("cards-shown-again")
    }

    func test_aCoveredCardCanBeShownOnItsOwn_andIsHiddenAgainOnRequest() {
        launch()
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))

        send(.toggleHideContents)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let card = cards.element(boundBy: 0)
        card.rightClick()
        XCTAssertTrue(app.menuItems["Show"].waitForExistence(timeout: 5), "a covered card offers Show")
        app.menuItems["Show"].click()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("one-card-shown-while-the-rest-are-hidden")

        card.rightClick()
        XCTAssertTrue(
            app.menuItems["Hide Again"].waitForExistence(timeout: 5),
            "a card shown by hand can be hidden again"
        )
        app.menuItems["Hide Again"].click()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        card.rightClick()
        XCTAssertTrue(
            app.menuItems["Show"].waitForExistence(timeout: 5),
            "hidden again, the card offers Show once more"
        )
        app.typeKey(.escape, modifierFlags: [])
    }
}
