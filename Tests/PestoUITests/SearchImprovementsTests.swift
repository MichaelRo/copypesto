// SPDX-License-Identifier: MIT
import XCTest

final class SearchImprovementsTests: PestoUITestCase {
    func test_openingSearch_letsYouTypeStraightAway() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        app.typeText("Quarterly")

        XCTAssertEqual(field.value as? String, "Quarterly", "the field was not focused after opening search")
    }

    func test_sensitiveFilter_showsOnlySensitiveClips() {
        launch()
        showOverlay()
        let target = card(containing: "Quarterly report draft")
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.rightClick()
        app.menuItems["Mark as Sensitive"].click()
        let sensitive = cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'"))
        XCTAssertTrue(sensitive.firstMatch.waitForExistence(timeout: 5))
        let total = cards.count
        XCTAssertGreaterThan(total, 1)

        element(AccessibilityID.searchButton).click()
        let chip = element(AccessibilityID.filterChip("Sensitive"))
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "no Sensitive filter chip")
        chip.click()

        // The chip shows every sensitive clip: the one marked by hand and the secrets Pesto hid on its own.
        let deadline = Date().addingTimeInterval(5)
        while cards.count >= total, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertLessThan(cards.count, total, "the filter should drop the clips that are not sensitive")
        XCTAssertGreaterThanOrEqual(cards.count, 1)
        XCTAssertTrue(sensitive.firstMatch.exists, "the clip marked sensitive should remain")
        capture("search-sensitive-only")
    }

    func test_commandA_selectsEveryClipShown() {
        launch()
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        let shown = cards.count

        overlay.typeKey("a", modifierFlags: .command)

        let label = app.staticTexts.matching(NSPredicate(format: "value == '\(shown) clips selected'")).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5), "expected \(shown) clips selected")
    }
}
