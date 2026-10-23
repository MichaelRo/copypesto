// SPDX-License-Identifier: MIT
import XCTest

final class SmartActionsTests: PestoUITestCase {
    /// The seeded "Team lunch is at 12:30 on Thursday..." note contains a date and time.
    func test_aClipWithADate_offersAddToCalendar() {
        launch()
        showOverlay()
        let target = card(containing: "Team lunch")
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.rightClick()

        XCTAssertTrue(app.menuItems["Add to Calendar"].waitForExistence(timeout: 5), "no Add to Calendar action")
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_aClipWithoutADate_doesNotOfferIt() {
        launch()
        showOverlay()
        let target = card(containing: "hello@example.com")
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        target.rightClick()

        XCTAssertTrue(app.menuItems["Compose Email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["Add to Calendar"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
