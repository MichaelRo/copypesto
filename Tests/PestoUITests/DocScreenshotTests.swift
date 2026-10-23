// SPDX-License-Identifier: MIT
import XCTest

/// The pictures in the README, docs and website: the real app, pesto-themed sample clips with two collections that
/// each have an icon and a colour of their own, over the branded backdrop so
/// the glass never shows the capture Mac's desktop.
/// `scripts/export-doc-images.sh`
/// copies them out of the newest `scripts/verify.sh` run.
final class DocScreenshotTests: PestoUITestCase {
    private func showShelf(mode: String, seed: String = "marketing") {
        launch(seed: seed, defaults: ["hasOnboarded": "true", "appearanceMode": mode], backdrop: "plain")
        showOverlay()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        parkPointer()
    }

    func test_shelf_dark() {
        showShelf(mode: "dark")
        capture("showcase-dark")
    }

    func test_shelf_light() {
        showShelf(mode: "light")
        capture("showcase-light")
    }

    func test_search() {
        showShelf(mode: "dark")
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("pine")
        XCTAssertTrue(card(containing: "pine nuts").waitForExistence(timeout: 5))
        capture("showcase-search")
    }

    func test_askPesto() {
        showShelf(mode: "dark")
        element(AccessibilityID.searchButton).click()
        XCTAssertTrue(element(AccessibilityID.searchField).waitForExistence(timeout: 5))
        app.typeText("the pesto link from today")
        let ask = element(AccessibilityID.askButton)
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.click()
        expectation(
            for: NSPredicate(format: "isSelected == true"),
            evaluatedWith: element(AccessibilityID.filterChip("Today"))
        )
        waitForExpectations(timeout: 5)
        capture("showcase-ask")
    }

    func test_collections() {
        showShelf(mode: "dark")
        let chip = element(AccessibilityID.collectionChip("Pesto night"))
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "the seeded collection has no chip")
        chip.click()
        XCTAssertTrue(card(containing: "Bring: basil").waitForExistence(timeout: 5), "the collection shows no clips")
        parkPointer()
        capture("showcase-collections")
    }

    func test_settingsCollections() {
        launch(seed: "marketing", defaults: ["hasOnboarded": "true", "appearanceMode": "dark"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Collections")).click()
        XCTAssertTrue(
            settingsWindow.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pesto night")).firstMatch
                .waitForExistence(timeout: 10),
            "no collection listed"
        )
        capture("showcase-settings-collections", of: settingsWindow)
    }

    /// On the smaller showcase seed: the marketing shelf is long enough that the card is off screen when it opens.
    func test_sensitiveCard() {
        showShelf(mode: "dark", seed: "showcase")
        let target = card(containing: "Shopping list")
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.rightClick()
        app.menuItems["Mark as Sensitive"].click()
        XCTAssertTrue(cards.matching(NSPredicate(format: "label CONTAINS 'sensitive content, hidden'"))
            .firstMatch.waitForExistence(timeout: 5))
        parkPointer()
        capture("showcase-sensitive")
    }

    /// The guide's most-seen pictures come as a pair, light and dark, so a reader sees the one that matches their page
    /// (the website swaps them by the reader's appearance). The three Settings panes are named `<pane>-light` and
    /// `<pane>-dark`; the shelf pair is `shelf-light` and `shelf-dark`.
    func test_settingsPanes_inBothModes() {
        for mode in ["light", "dark"] {
            if mode == "dark" { app.terminate() }
            launch(seed: "marketing", defaults: ["hasOnboarded": "true", "appearanceMode": mode])
            send(.openSettings)
            XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
            for pane in ["General", "Appearance", "Privacy"] {
                element(AccessibilityID.settingsSidebar(pane)).click()
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                capture("settingspane-\(pane.lowercased())-\(mode)", of: settingsWindow)
            }
        }
    }
}
