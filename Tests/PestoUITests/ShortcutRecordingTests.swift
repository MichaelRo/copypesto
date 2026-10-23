// SPDX-License-Identifier: MIT
import XCTest

/// The shortcut recorders in Settings → Shortcuts. Global hotkeys are off in a UI-test launch, so what can be proved
/// here is the recorder itself: the combination already in use can be recorded again, a clash is refused with its
/// reason, Esc cancels, and an optional shortcut is recorded and turned off. Every row has one trailing menu with
/// Change, Reset to Default and Turn Off.
final class ShortcutRecordingTests: PestoUITestCase {
    private let shelfID: UInt32 = 1
    private let pinnedWindowID: UInt32 = 13

    private func openShortcuts() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
        element(AccessibilityID.settingsSidebar("Shortcuts")).click()
    }

    private func value(of id: String) -> String {
        "\(element(id).value ?? "")"
    }

    private func choose(_ item: String, inMenuOf id: UInt32) {
        let menu = element(AccessibilityID.shortcutMenu(id))
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "row \(id) has no menu")
        menu.click()
        let entry = app.menuItems[item].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "no \(item) in the menu of row \(id)")
        entry.click()
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    }

    func test_theShortcutInUse_canBeRecordedAgain_aClashIsRefused_andEscCancels() {
        openShortcuts()
        let shelf = element(AccessibilityID.shortcutRecorder(shelfID))
        XCTAssertTrue(shelf.waitForExistence(timeout: 5))
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(shelfID)), "⇧⌘V")

        shelf.click()
        app.typeKey("v", modifierFlags: [.command, .shift])
        settle()
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(shelfID)), "⇧⌘V", "recording the one in use failed")

        shelf.click()
        app.typeKey("v", modifierFlags: [.command, .option])
        settle()
        let refusal = settingsWindow.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS 'already the shortcut for' OR value CONTAINS 'already the shortcut for'"
        )).firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 5), "a clash gave no reason")
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(shelfID)), "⇧⌘V")
        capture("settings-shortcut-clash", of: settingsWindow)

        shelf.click()
        app.typeKey(.escape, modifierFlags: [])
        settle()
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(shelfID)), "⇧⌘V", "Esc changed the shortcut")
    }

    func test_anOptionalShortcut_startsUnset_isRecorded_andCleared() {
        openShortcuts()
        let recorder = element(AccessibilityID.shortcutRecorder(pinnedWindowID))
        XCTAssertTrue(recorder.waitForExistence(timeout: 5))
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(pinnedWindowID)), "Not set")

        recorder.click()
        app.typeKey("p", modifierFlags: [.control, .option])
        settle()
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(pinnedWindowID)), "⌃⌥P")
        capture("settings-shortcuts-recorded", of: settingsWindow)

        choose("Turn Off", inMenuOf: pinnedWindowID)
        settle()
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(pinnedWindowID)), "Not set")
    }

    func test_changeInTheMenu_startsRecording() {
        openShortcuts()
        let recorder = element(AccessibilityID.shortcutRecorder(shelfID))
        XCTAssertTrue(recorder.waitForExistence(timeout: 5))

        choose("Change…", inMenuOf: shelfID)
        app.typeKey("b", modifierFlags: [.command, .option, .shift])
        settle()

        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(shelfID)), "⌥⇧⌘B")
    }

    func test_theMenu_offersResetOnlyWhenTheShortcutDiffersFromItsDefault() {
        openShortcuts()
        let menu = element(AccessibilityID.shortcutMenu(shelfID))
        XCTAssertTrue(menu.waitForExistence(timeout: 5))

        menu.click()
        XCTAssertTrue(app.menuItems["Turn Off"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["Reset to Default"].firstMatch.exists, "Reset offered at the default")
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_doubleCopyAppend_livesWithTheShortcuts() {
        openShortcuts()

        XCTAssertTrue(element(AccessibilityID.doubleCopyToggle).waitForExistence(timeout: 5))
        capture("settings-general-shortcuts", of: settingsWindow)
    }

    func test_aShortcutWithADefault_canBeTurnedOffAndReset() {
        openShortcuts()
        let plainTextID: UInt32 = 12
        let recorder = element(AccessibilityID.shortcutRecorder(plainTextID))
        XCTAssertTrue(recorder.waitForExistence(timeout: 5))
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(plainTextID)), "⌃⌥⌘V")

        choose("Turn Off", inMenuOf: plainTextID)
        settle()
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(plainTextID)), "Not set")

        choose("Reset to Default", inMenuOf: plainTextID)
        settle()
        XCTAssertEqual(value(of: AccessibilityID.shortcutRecorder(plainTextID)), "⌃⌥⌘V")
    }
}
