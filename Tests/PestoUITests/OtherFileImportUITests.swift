// SPDX-License-Identifier: MIT
import XCTest

/// Other File…: a CSV of clips from an app Pesto has no reader for. A UI-test launch names the fixture file
/// (`PESTO_UITEST_IMPORT_FIXTURE=otherfile`) because the file panel cannot be driven.
final class OtherFileImportUITests: PestoUITestCase {
    func test_otherFile_mapsTheColumns_thenShowsTheUsualPreview() {
        launch(importFixture: "otherfile")
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Data")).click()
        let menu = element(AccessibilityID.importFromAppMenu)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no Import menu")

        menu.click()
        app.menuItems["Other File\u{2026}"].click()

        let sheet = element(AccessibilityID.otherFileSheet)
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Other File… did not open its sheet")
        capture("other-file-sheet", of: settingsWindow)

        element(AccessibilityID.otherFileContinueButton).click()

        XCTAssertTrue(
            element(AccessibilityID.importPreviewSheet).waitForExistence(timeout: 10),
            "the usual import preview did not follow"
        )
        element(AccessibilityID.importPreviewCancel).click()
    }
}
