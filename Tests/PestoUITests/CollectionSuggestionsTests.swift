// SPDX-License-Identifier: MIT
import XCTest

/// Settings → Collections offers collections built from the history (or starters, while it is short). Adding one makes
/// a smart collection, and the suggestion goes away.
final class CollectionSuggestionsTests: PestoUITestCase {
    private func openCollections() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Collections")).click()
    }

    func test_aSuggestedCollection_isAddedAsASmartCollection_andLeavesTheList() {
        openCollections()
        let add = element(AccessibilityID.addSuggestedCollection("shape-links"))
        XCTAssertTrue(add.waitForExistence(timeout: 15), "no Links suggestion in a history with links")
        capture("settings-collections-suggestions", of: settingsWindow)

        add.click()

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: add)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(
            settingsWindow.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Links")).firstMatch
                .waitForExistence(timeout: 5),
            "the new collection is not listed"
        )
        XCTAssertTrue(
            settingsWindow.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Smart collection")).firstMatch
                .waitForExistence(timeout: 5),
            "it is not a smart collection"
        )
        capture("settings-collections-after-add", of: settingsWindow)
    }

    func test_aDismissedSuggestion_staysAway() {
        openCollections()
        let add = element(AccessibilityID.addSuggestedCollection("shape-code"))
        XCTAssertTrue(add.waitForExistence(timeout: 15))

        settingsWindow.buttons["Dismiss Code"].click()

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: add)
        waitForExpectations(timeout: 8)
        element(AccessibilityID.settingsSidebar("Appearance")).click()
        element(AccessibilityID.settingsSidebar("Collections")).click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(add.exists, "a dismissed suggestion came back")
    }
}
