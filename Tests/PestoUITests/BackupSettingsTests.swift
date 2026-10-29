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

        let summary = element(AccessibilityID.backupStatus)
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "no backup summary row")
        XCTAssertTrue(
            summary.label.contains("Your clips stay on this Mac") && summary.label.contains("Backup: Off"),
            "the Data pane should say, in words, that the clips stay here and backup is off: \(summary.label)"
        )
        XCTAssertTrue(element(AccessibilityID.backupSwitch).exists, "no switch for backing up this Mac")
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
        let setUp = element(AccessibilityID.backupSwitch)
        XCTAssertTrue(setUp.waitForExistence(timeout: 5), "the Data pane has no switch to back up this Mac")
        setUp.click()

        let confirm = element(AccessibilityID.backupSaveButton)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the Back up this Mac switch did not open the set-up sheet")
        XCTAssertFalse(confirm.isEnabled)

        settingsWindow.sheets.firstMatch.buttons["Cancel"].click()
        XCTAssertFalse(confirm.waitForExistence(timeout: 2), "Cancel left the sheet open")
        XCTAssertTrue(setUp.exists, "cancelling must leave the backup not set up")
        XCTAssertTrue(
            element(AccessibilityID.backupStatus).label.contains("Backup: Off"),
            "cancelling must leave the backup off"
        )
        XCTAssertFalse(element(AccessibilityID.autoBackupNowButton).exists)
    }

    func test_thereIsOneBackupSection_notAManualOneAndAnAutomaticOne() {
        openDataPane()
        XCTAssertTrue(element(AccessibilityID.backupSwitch).waitForExistence(timeout: 5))
        XCTAssertTrue(element(AccessibilityID.restoreBackupButton).exists)
        XCTAssertFalse(settingsWindow.buttons["Back Up\u{2026}"].exists, "the separate manual backup is back")
        XCTAssertFalse(settingsWindow.staticTexts["Automatic backup"].exists, "a second backup section is back")
    }

    func test_theBackupSheet_offersARecoveryKeyInsteadOfAPassphrase() {
        openDataPane()
        element(AccessibilityID.backupSwitch).click()
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
            settingsWindow.sheets.firstMatch.checkBoxes["Back up automatically"].exists,
            "the sheet does not offer to back up automatically"
        )
        capture("backup-sheet-passphrase", of: settingsWindow)
    }
}
