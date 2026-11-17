// SPDX-License-Identifier: MIT
import XCTest

final class PasteboardAccessUITests: PestoUITestCase {
    private let warningMenuTitle = "Clipboard Access Limited \u{2014} Open Settings\u{2026}"

    func test_whenPasteboardAccessIsBlocked_thenStatusMenuAndSettingsWarn() {
        launch(pasteboardAccess: "blocked")

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitUntilExists(timeout: 10), "no menu-bar item")
        statusItem.click()
        XCTAssertTrue(
            app.menuItems[warningMenuTitle].waitUntilExists(timeout: 5),
            "status menu should warn when pasteboard access is blocked"
        )
        let openSettings = app.menuItems.matching(identifier: "statusOpenSettings").firstMatch
        XCTAssertTrue(openSettings.exists, "Settings menu item missing")
        openSettings.click()

        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10), "Settings did not open")
        XCTAssertTrue(
            settingsWindow.staticTexts["Clipboard capture is blocked"].waitUntilExists(timeout: 5),
            "Settings should show blocked clipboard capture warning"
        )
    }

    func test_whenPasteboardAccessIsPrompting_thenStatusMenuAndSettingsWarn() {
        launch(pasteboardAccess: "prompting")

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitUntilExists(timeout: 10), "no menu-bar item")
        statusItem.click()
        XCTAssertTrue(
            app.menuItems[warningMenuTitle].waitUntilExists(timeout: 5),
            "status menu should warn when pasteboard access is prompting"
        )
        let openSettings = app.menuItems.matching(identifier: "statusOpenSettings").firstMatch
        XCTAssertTrue(openSettings.exists, "Settings menu item missing")
        openSettings.click()

        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10), "Settings did not open")
        XCTAssertTrue(
            settingsWindow.staticTexts["macOS asks before Pesto reads the clipboard"].waitUntilExists(timeout: 5),
            "Settings should show prompting clipboard warning"
        )
    }

    func test_whenPasteboardAccessIsAllowed_thenWarningsAreHidden() {
        launch(pasteboardAccess: "allowed")

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitUntilExists(timeout: 10), "no menu-bar item")
        statusItem.click()
        XCTAssertTrue(app.menuItems.matching(identifier: "statusOpenSettings").firstMatch.waitUntilExists(timeout: 5))
        XCTAssertFalse(
            app.menuItems[warningMenuTitle].exists,
            "status menu should hide warning when pasteboard access is allowed"
        )
        app.menuItems.matching(identifier: "statusOpenSettings").firstMatch.click()

        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10))
        XCTAssertFalse(settingsWindow.staticTexts["Clipboard capture is blocked"].exists)
        XCTAssertFalse(settingsWindow.staticTexts["macOS asks before Pesto reads the clipboard"].exists)
    }
}
