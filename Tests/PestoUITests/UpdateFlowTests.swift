// SPDX-License-Identifier: MIT
import XCTest

final class UpdateFlowTests: PestoUITestCase {
    private func launchWithFakeUpdater() {
        launch(defaults: ["hasOnboarded": "true"], updates: true)
    }

    private func openGeneral() {
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("General")).click()
    }

    private func installCount() -> Int {
        let log = (try? String(
            contentsOf: workDirectory.appendingPathComponent("commands.log"), encoding: .utf8
        )) ?? ""
        return log.components(separatedBy: "\n").count { $0.hasPrefix("update-install") }
    }

    private func waitForInstalls(_ count: Int) {
        let deadline = Date().addingTimeInterval(5)
        while installCount() < count, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    func test_generalPane_offersTheSwitchesAndCheckNow_andAStagedUpdateOffersRestartAndWhatsNew() {
        launchWithFakeUpdater()
        openGeneral()

        let checkNow = settingsWindow.buttons["Check Now"]
        XCTAssertTrue(checkNow.waitForExistence(timeout: 5), "no Check Now button in General")
        XCTAssertTrue(
            settingsWindow.staticTexts["Not checked yet."].exists,
            "before any check the pane should say so"
        )
        let installSwitch = element(AccessibilityID.settingsChoice("installUpdates", "toggle"))
        XCTAssertTrue(installSwitch.exists, "no Install updates automatically switch")
        let before = installSwitch.value as? Int
        installSwitch.click()
        XCTAssertNotEqual(installSwitch.value as? Int, before, "the switch did not flip")
        XCTAssertFalse(settingsWindow.buttons["Restart Now"].exists, "nothing is staged yet")

        checkNow.click()

        XCTAssertTrue(
            settingsWindow.buttons["Restart Now"].waitForExistence(timeout: 10),
            "a staged update should offer Restart Now"
        )
        XCTAssertTrue(settingsWindow.links["What\u{2019}s New"].exists, "a staged update should offer What's New")
        XCTAssertFalse(settingsWindow.staticTexts["Not checked yet."].exists)

        settingsWindow.buttons["Restart Now"].click()
        waitForInstalls(1)
        XCTAssertEqual(installCount(), 1, "Restart Now did not run the staged install")
    }

    func test_checkForUpdatesInTheMenu_toastsThenClickingTheToastRestarts_andTheMenuOffersRestartToo() {
        launchWithFakeUpdater()
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "no menu-bar item")

        statusItem.click()
        XCTAssertFalse(
            app.menuItems.matching(identifier: "statusInstallStagedUpdate").firstMatch.exists,
            "nothing is staged yet, so no Restart to Update"
        )
        let check = app.menuItems["Check for Updates\u{2026}"]
        XCTAssertTrue(check.waitForExistence(timeout: 5), "no Check for Updates in the menu")
        check.click()

        let readyText = "A new version is ready"
        let toast = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", readyText, readyText)
        ).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "no update-ready toast after a manual check")
        capture("update-ready-toast")
        toast.click()
        waitForInstalls(1)
        XCTAssertEqual(installCount(), 1, "clicking the toast did not run the staged install")

        statusItem.click()
        let restart = app.menuItems.matching(identifier: "statusInstallStagedUpdate").firstMatch
        XCTAssertTrue(restart.waitForExistence(timeout: 5), "the menu should keep offering Restart to Update")
        XCTAssertTrue(app.menuItems.matching(identifier: "statusShowWhatsNew").firstMatch.exists)
        restart.click()
        waitForInstalls(2)
        XCTAssertEqual(installCount(), 2, "the menu's Restart to Update did not run the staged install")
    }

    func test_developmentBuild_checkForUpdatesShowsUnavailableToast() {
        launch(defaults: ["hasOnboarded": "true"])
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "no menu-bar item")

        statusItem.click()
        let check = statusItem.menuItems["statusCheckUpdates"]
        XCTAssertTrue(check.waitForExistence(timeout: 5), "no Check for Updates in the menu")
        check.click()

        let unavailableText = "This build does not check for updates."
        let toast = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", unavailableText, unavailableText)
        ).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "no unavailable-updates toast on development build")
    }
}
