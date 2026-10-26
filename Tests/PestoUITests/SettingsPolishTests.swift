// SPDX-License-Identifier: MIT
import XCTest

/// The Settings window's own conveniences: a live preview, tiles, and search.
final class SettingsPolishTests: PestoUITestCase {
    private func openSettings(pane: String) {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar(pane)).click()
    }

    private var previewCards: XCUIElementQuery {
        settingsWindow.descendants(matching: .any).matching(identifier: AccessibilityID.settingsPreviewCard)
    }

    func test_appearancePreview_followsTheCardSizeSlider() {
        openSettings(pane: "Appearance")
        XCTAssertTrue(previewCards.firstMatch.waitForExistence(timeout: 5), "no live preview")
        let medium = previewCards.firstMatch.frame.width

        element(AccessibilityID.settingsChoice("cardWidth", "slider")).adjust(toNormalizedSliderPosition: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        XCTAssertLessThan(previewCards.firstMatch.frame.width, medium - 10, "the preview did not shrink for Small")
        capture("settings-live-preview", of: settingsWindow)
    }

    func test_settingsSearchField_doesNotTakeFocusWhenAPaneOpens() {
        openSettings(pane: "Privacy")
        let field = settingsWindow.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field in Settings")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(
            (field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false,
            "the search field has focus and draws its ring in every Settings picture"
        )
    }

    func test_settingsSearch_findsASettingAndOpensItsPane() {
        openSettings(pane: "General")
        let field = settingsWindow.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field in Settings")
        field.click()
        field.typeText("blur")

        let result = element(AccessibilityID.settingsSearchResult("Sensitive content filter"))
        XCTAssertTrue(result.waitForExistence(timeout: 5), "searching for blur found nothing")
        result.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("settings-search-after-click", of: settingsWindow)

        XCTAssertTrue(
            element(AccessibilityID.settingsChoice("nsfwMode", "blur")).waitForExistence(timeout: 5),
            "the result did not open the Capture pane"
        )
    }

    func test_settingsSearch_scrollsToARowThatStartsBelowTheFold() {
        openSettings(pane: "Data")
        let clear = element(AccessibilityID.clearEverythingButton)
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        let window = settingsWindow.frame
        XCTAssertGreaterThan(
            clear.frame.maxY,
            window.maxY,
            "Clear Everything is already on screen, so this proves nothing"
        )

        let field = settingsWindow.searchFields.firstMatch
        field.click()
        field.typeText("clear everything")
        let result = element(AccessibilityID.settingsSearchResult("Clear Everything"))
        XCTAssertTrue(result.waitForExistence(timeout: 5), "searching found nothing")
        result.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        capture("settings-search-scrolled", of: settingsWindow)

        XCTAssertLessThan(clear.frame.maxY, window.maxY, "the result opened the pane but left its row below the fold")
        XCTAssertGreaterThan(clear.frame.minY, window.minY)
    }

    func test_settingsSearch_scrollsWithinAPaneThatIsAlreadyOpen() {
        openSettings(pane: "Data")
        let field = settingsWindow.searchFields.firstMatch
        field.click()
        field.typeText("rebuild")
        let result = element(AccessibilityID.settingsSearchResult("Rebuild search index"))
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let rebuild = settingsWindow.buttons["Rebuild search index"]
        XCTAssertTrue(rebuild.waitForExistence(timeout: 5))
        XCTAssertLessThan(rebuild.frame.maxY, settingsWindow.frame.maxY)
        XCTAssertGreaterThan(rebuild.frame.minY, settingsWindow.frame.minY)
    }

    func test_settings_shelfSuggestionsToggleAndReset() {
        openSettings(pane: "General")
        let toggle = element(AccessibilityID.shelfSuggestionsSettingsToggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no shelf suggestions toggle in General settings")
        let resetButton = element(AccessibilityID.resetSuggestionsButton)
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5), "no reset suggestions button in General settings")
    }
}
