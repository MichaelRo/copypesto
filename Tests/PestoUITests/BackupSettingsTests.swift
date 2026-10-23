// SPDX-License-Identifier: MIT
import XCTest

final class BackupSettingsTests: PestoUITestCase {
    private func openDataPane() {
        launch(defaults: ["hasOnboarded": "true"])
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Data")).click()
    }

    /// A person could not tell whether backup was on: the answer was only which buttons were showing.
    func test_theDataPane_saysWhetherBackupIsOn() {
        openDataPane()

        XCTAssertTrue(element(AccessibilityID.backupStatus).waitForExistence(timeout: 5), "no backup status row")
        XCTAssertTrue(
            settingsWindow.staticTexts["Backup is off"].waitForExistence(timeout: 5),
            "the Data pane should say, in words, that backup is off"
        )
        capture("settings-data-backup-off", of: settingsWindow)
    }

    func test_clearEverything_isLastInData_notInPrivacy() {
        openDataPane()
        XCTAssertTrue(element(AccessibilityID.clearEverythingButton).waitForExistence(timeout: 5))

        element(AccessibilityID.settingsSidebar("Privacy")).click()

        XCTAssertFalse(element(AccessibilityID.clearEverythingButton).exists, "Clear Everything moved to Data")
    }

    func test_restoreSheet_opensFromTheDataPane() {
        openDataPane()
        let restore = element(AccessibilityID.restoreBackupButton)
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.click()

        XCTAssertTrue(app.staticTexts["Restore from Backup"].waitForExistence(timeout: 5))
    }

    func test_theBackupSheet_keepsSetUpDisabledUntilAFolderIsChosen_andCancelLeavesNothingSetUp() {
        openDataPane()
        let setUp = element(AccessibilityID.setUpBackupButton)
        XCTAssertTrue(setUp.waitForExistence(timeout: 5), "the Data pane has no way to set up a backup")
        setUp.click()

        let confirm = element(AccessibilityID.backupSaveButton)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Set Up Backup did not open its sheet")
        XCTAssertFalse(confirm.isEnabled)

        settingsWindow.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertFalse(confirm.waitForExistence(timeout: 2), "Cancel left the sheet open")
        XCTAssertTrue(setUp.exists, "cancelling must leave the backup not set up")
        XCTAssertFalse(element(AccessibilityID.autoBackupNowButton).exists)
    }

    func test_thereIsOneBackupSection_notAManualOneAndAnAutomaticOne() {
        openDataPane()
        XCTAssertTrue(element(AccessibilityID.setUpBackupButton).waitForExistence(timeout: 5))
        XCTAssertTrue(element(AccessibilityID.restoreBackupButton).exists)
        XCTAssertFalse(settingsWindow.buttons["Back Up\u{2026}"].exists, "the separate manual backup is back")
        XCTAssertFalse(settingsWindow.staticTexts["Automatic backup"].exists, "a second backup section is back")
    }

    func test_theBackupSheet_offersARecoveryKeyInsteadOfAPassphrase() {
        openDataPane()
        element(AccessibilityID.setUpBackupButton).click()
        let protection = element(AccessibilityID.settingsChoice("autoBackup", "protection"))
        XCTAssertTrue(protection.waitForExistence(timeout: 5), "the sheet has no choice of protection")
        XCTAssertFalse(
            element(AccessibilityID.backupPassphraseField).exists,
            "a recovery key needs no passphrase, so none should be asked for"
        )
        XCTAssertTrue(
            (protection.radioButtons["Recovery key only"].value as? Int) == 1,
            "the recovery key should be the default protection"
        )
        capture("backup-sheet", of: settingsWindow)

        protection.radioButtons["Passphrase"].click()

        XCTAssertTrue(element(AccessibilityID.backupPassphraseField).waitForExistence(timeout: 5))
        XCTAssertTrue(
            settingsWindow.sheets.firstMatch.checkBoxes["Keep it up to date automatically"].exists,
            "the sheet does not offer to keep the backup up to date"
        )
        capture("backup-sheet-passphrase", of: settingsWindow)
    }
}
