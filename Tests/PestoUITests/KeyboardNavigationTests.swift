// SPDX-License-Identifier: MIT
import XCTest

final class KeyboardNavigationTests: PestoUITestCase {
    func test_arrowKeysAndReturn_pasteTheFocusedCard() {
        launch()
        showOverlay()
        // The first card shows its detail popover after a short delay; keys must work with it open, too.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        overlay.typeKey(.rightArrow, modifierFlags: [])
        overlay.typeKey(.return, modifierFlags: [])

        XCTAssertEqual(
            waitForPaste(count: 1),
            ["Team lunch is at 12:30 on Thursday, booked under Alex."],
            "Right then Return should paste the second-newest card"
        )
    }

    func test_hoveringAnotherCard_doesNotMoveKeyboardFocus() {
        launch()
        showOverlay()
        card(containing: "hello@example.com").hover()
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        overlay.typeKey(.rightArrow, modifierFlags: [])
        overlay.typeKey(.return, modifierFlags: [])

        XCTAssertEqual(
            waitForPaste(count: 1),
            ["Team lunch is at 12:30 on Thursday, booked under Alex."],
            "the pointer resting on the third card must not decide where the arrow keys start"
        )
    }

    /// The grid's key monitor is app-wide. With the overlay still visible, typing in Settings was
    /// swallowed by the grid (letters became a search, Backspace opened a delete alert).
    func test_typingInSettings_isNotSwallowedByTheOverlayGrid() {
        launch()
        showOverlay()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Privacy")).click()
        let field = settingsWindow.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Settings has no search field")

        field.click()
        field.typeText("abc")

        XCTAssertEqual(field.value as? String, "abc", "keys typed in Settings must reach the field")
    }
}

/// Settings, New collection and Merge were unreachable from the keyboard while the
/// grid held focus (Tab was consumed and did nothing; unhandled Cmd-keys were silently swallowed).
final class ToolbarShortcutTests: PestoUITestCase {
    func test_cmdComma_opensSettingsFromTheGrid() {
        launch()
        showOverlay()

        overlay.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
    }

    func test_cmdN_startsANewCollectionFromTheGrid() {
        launch()
        showOverlay()

        overlay.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(element(AccessibilityID.collectionNameField).waitForExistence(timeout: 5))
    }
}

final class SearchKeyboardTests: PestoUITestCase {
    /// There was no key that pasted a search result.
    func test_returnInSearch_pastesTheTopResult() {
        launch()
        showOverlay()
        element(AccessibilityID.searchButton).click()
        let field = element(AccessibilityID.searchField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeText("Quarterly")
        XCTAssertTrue(card(containing: "Quarterly report draft").waitForExistence(timeout: 5))

        app.typeKey(.return, modifierFlags: [])

        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: overlay)
        waitForExpectations(timeout: 5)
    }
}
