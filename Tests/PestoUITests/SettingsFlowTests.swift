// SPDX-License-Identifier: MIT
import XCTest

final class SettingsFlowTests: PestoUITestCase {
    func test_everySettingsPane_opens() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), "Settings window did not open")

        for section in [
            "General",
            "Appearance",
            "Privacy",
            "Collections",
            "Snippets",
            "Data"
        ] {
            let row = element(AccessibilityID.settingsSidebar(section))
            XCTAssertTrue(row.waitForExistence(timeout: 5), "sidebar row \(section) missing")
            row.click()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            XCTAssertTrue(settingsWindow.exists, "Settings closed while opening \(section)")
            capture("settings-\(section.replacingOccurrences(of: " & ", with: "-"))", of: settingsWindow)
        }
    }

    func test_settingsAskedToOpenAtAPane_opensOnThatPane() {
        launch()
        send(.openSettingsAtData)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), "Settings window did not open")

        let data = element(AccessibilityID.settingsSidebar("Data"))
        XCTAssertTrue(data.waitForExistence(timeout: 5))
        XCTAssertTrue(data.isSelected, "Settings opened on another pane than the one it was asked for")
    }

    func test_captureSettings_listsTheAppsThatAreAlwaysExcluded() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Privacy")).click()

        XCTAssertTrue(
            element(AccessibilityID.allowExclusion("com.1password.1password")).waitForExistence(timeout: 5),
            "1Password is excluded but not listed with its Allow control"
        )
        capture("settings-built-in-exclusions", of: settingsWindow)
    }

    /// Window order and activation are what these two tests measure, and macOS answers an activation request for a
    /// bundle ID with whichever copy of that app is already running, such as a Pesto installed with `make install`.
    private func skipWhileAnotherPestoRuns() throws {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "net.copypesto.pesto")
        try XCTSkipUnless(others.isEmpty, "Quit the running Pesto first: its window state would answer for the test's")
    }

    func test_openingSettingsAgain_keepsOneWindowAndRaisesIt() throws {
        try skipWhileAnotherPestoRuns()
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))

        send(.openSettings)
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        XCTAssertEqual(app.windows.matching(identifier: AccessibilityID.settingsWindow).count, 1)
        XCTAssertTrue(settingsWindow.isHittable, "the existing Settings window should be in front")
    }

    /// Opened from the shelf (a non-activating panel), another app is still the active one, and macOS refuses a
    /// cooperative activation: Settings used to appear behind that app.
    func test_settings_opensInFrontWhenAnotherAppIsActive() throws {
        try skipWhileAnotherPestoRuns()
        launch()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(finder.state, .runningForeground)

        send(.openSettings)

        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(5)
        while app.state != .runningForeground,
              Date() < deadline
        {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "Pesto did not become the active app, so Settings sits behind Finder"
        )
        XCTAssertTrue(settingsWindow.isHittable)
    }

    /// The switch is always usable. Under test the login-item backend refuses, which is what macOS does for a copy it
    /// will not register, so the person is told why and the switch stays off.
    func test_launchAtLogin_whenMacOSRefuses_staysOffAndSaysWhy() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("General")).click()

        let toggle = element(AccessibilityID.launchAtLoginToggle)
        XCTAssertTrue(toggle.isEnabled, "a switch that cannot be pressed never gets to ask macOS")
        toggle.click()

        XCTAssertTrue(
            element(AccessibilityID.launchAtLoginUnavailable).waitForExistence(timeout: 5),
            "a refused switch gives no reason"
        )
        XCTAssertEqual("\(toggle.value ?? "")", "0")
    }

    func test_closingSettings_keepsTheAppRunning() {
        // Regression: closing Settings quit the whole app, taking the menu-bar item, hotkey and
        // pasteboard watcher with it.
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))

        settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertNotEqual(app.state, .notRunning, "closing Settings terminated the app")
        showOverlay()
    }

    func test_menuBarIcon_canBeHidden_andComesBack() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("General")).click()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "no menu-bar icon to hide")

        let toggle = element(AccessibilityID.settingsChoice("menuBarIcon", "toggle"))
        XCTAssertEqual("\(toggle.value ?? "")", "1")
        toggle.click()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: statusItem)
        waitForExpectations(timeout: 8)
        capture("settings-menu-bar-icon-hidden", of: settingsWindow)

        toggle.click()
        expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.statusItems.firstMatch)
        waitForExpectations(timeout: 8)
    }

    func test_dataImport_isOneMenuOfSources_notAButtonForOneApp() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Data")).click()

        let menu = element(AccessibilityID.importFromAppMenu)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no import menu in Data")
        menu.click()

        XCTAssertTrue(element(AccessibilityID.importPasteButton).waitForExistence(timeout: 5), "Paste is not offered")
        XCTAssertTrue(element(AccessibilityID.importMaccyButton).exists, "Maccy is not offered")
        XCTAssertTrue(element(AccessibilityID.importAlfredButton).exists, "Alfred is not offered")
        XCTAssertTrue(element(AccessibilityID.importSnippetsButton).exists, "a snippets file is not offered")
        capture("settings-data-import-menu", of: settingsWindow)
        app.typeKey(.escape, modifierFlags: [])
    }
}
