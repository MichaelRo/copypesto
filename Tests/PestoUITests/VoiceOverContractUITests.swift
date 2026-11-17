// SPDX-License-Identifier: MIT
import XCTest

final class VoiceOverContractUITests: PestoUITestCase {
    func test_whenInspectingSettingsControls_thenPopUpPickersDisclosuresAndTilesAreExposed() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10), "Settings window did not open")

        // Tiles in Appearance
        element(AccessibilityID.settingsSidebar("Appearance")).click()
        let solidTile = element(AccessibilityID.settingsChoice("shelfSurface", "solid"))
        let glassTile = element(AccessibilityID.settingsChoice("shelfSurface", "glass"))
        XCTAssertTrue(solidTile.waitUntilExists(timeout: 5), "Solid tile missing from AX tree")
        XCTAssertTrue(glassTile.exists, "Glass tile missing from AX tree")

        // PopUpMenuButton / Picker in Data
        element(AccessibilityID.settingsSidebar("Data")).click()
        let retentionPicker = element(AccessibilityID.settingsChoice("retention", "age"))
        XCTAssertTrue(retentionPicker.waitUntilExists(timeout: 5), "Settings Data retention picker missing")

        // Disclosure in Privacy
        element(AccessibilityID.settingsSidebar("Privacy")).click()
        let disclosures = settingsWindow.disclosureTriangles
        XCTAssertGreaterThan(disclosures.count, 0, "Privacy disclosure triangle missing")
    }

    func test_whenInspectingCards_thenCustomContentDetailsTextAndCustomActionsExist() {
        launch()
        showOverlay()

        let firstCard = cards.firstMatch
        XCTAssertTrue(firstCard.waitUntilExists(timeout: 10), "first card missing")
        XCTAssertFalse(firstCard.label.isEmpty, "card must expose a non-empty accessibility label")
        XCTAssertEqual(firstCard.identifier, AccessibilityID.card)

        // Verify card actions are reachable via context menu
        firstCard.rightClick()
        XCTAssertTrue(app.menuItems["Paste"].waitUntilExists(timeout: 5), "Paste action missing")
        XCTAssertTrue(app.menuItems["Copy"].exists, "Copy action missing")
        XCTAssertTrue(app.menuItems["Quick Look"].exists, "Quick Look action missing")
        overlay.typeKey(.escape, modifierFlags: [])
    }
}
