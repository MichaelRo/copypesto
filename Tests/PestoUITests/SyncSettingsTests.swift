// SPDX-License-Identifier: MIT
import XCTest

final class SyncSettingsTests: PestoUITestCase {
    private func openDataPane() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Data")).click()
    }

    func test_syncIsOffUntilTurnedOn_andTheSheetSaysWhatItDoes() {
        openDataPane()
        let toggle = element(AccessibilityID.syncSwitch)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no sync switch in the Data pane")
        XCTAssertFalse(element(AccessibilityID.syncStatus).exists, "a sync status shows while sync is off")

        toggle.click()

        XCTAssertTrue(app.staticTexts["Sync with iCloud Drive"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(AccessibilityID.syncTurnOnButton).exists)
        capture("settings-data-sync-setup", of: settingsWindow)
    }

    func test_turningSyncOn_showsTheRecoveryKey_thenARealStatus_andLeaveTurnsItOff() {
        openDataPane()
        element(AccessibilityID.syncSwitch).click()
        element(AccessibilityID.syncTurnOnButton).click()
        XCTAssertTrue(app.staticTexts["Your recovery key"].waitForExistence(timeout: 10))
        app.buttons["Done"].click()

        let status = element(AccessibilityID.syncStatus)
        XCTAssertTrue(status.waitForExistence(timeout: 10), "no sync status after turning sync on")
        XCTAssertFalse(status.label.contains("Connected"), "sync must not claim to be connected: \(status.label)")
        capture("settings-data-sync-on", of: settingsWindow)

        element(AccessibilityID.syncPauseButton).click()
        waitForNonExistence(element(AccessibilityID.syncStatus), timeout: 5, "the sync status stays after Pause Sync")
    }
}
