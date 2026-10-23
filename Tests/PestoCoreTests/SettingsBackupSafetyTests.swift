// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Restoring a settings file cannot weaken security or wipe history")
struct SettingsBackupSafetyTests {
    @discardableResult
    private func restore(
        _ settings: [String: Any], approving: Set<String> = [],
        notifying center: NotificationCenter = NotificationCenter()
    ) throws
        -> SettingsBackupManager.RestoreResult
    {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "settings": settings])
        return try SettingsBackupManager.restore(from: data, approving: approving, into: defaults, notifying: center)
    }

    private let defaults = ThrowawayDefaults.make()

    @Test("lock, screen-sharing and exclusion settings are neither exported nor restored")
    func whenRestoring_thenSecurityKeysAreLeftAlone() throws {
        defaults.set(true, forKey: "biometricLockEnabled")
        defaults.set(true, forKey: "screenSharingPrivacy")
        defaults.set("com.example.vault", forKey: "additionalExcludedBundleIDs")
        defer {
            for key in ["biometricLockEnabled", "screenSharingPrivacy", "additionalExcludedBundleIDs"] {
                defaults.removeObject(forKey: key)
            }
        }

        try restore([
            "biometricLockEnabled": false, "screenSharingPrivacy": false, "additionalExcludedBundleIDs": ""
        ])

        #expect(defaults.bool(forKey: "biometricLockEnabled"))
        #expect(defaults.bool(forKey: "screenSharingPrivacy"))
        #expect(defaults.string(forKey: "additionalExcludedBundleIDs") == "com.example.vault")
        let exported = try #require(
            JSONSerialization.jsonObject(with: SettingsBackupManager.export(from: defaults)) as? [String: Any]
        )
        let keys = Set((exported["settings"] as? [String: Any])?.keys.map(\.self) ?? [])
        #expect(keys.isDisjoint(with: [
            "biometricLockEnabled",
            "screenSharingPrivacy",
            "additionalExcludedBundleIDs"
        ]))
    }

    @Test("the theme and the app icon travel in a settings file, and an unknown name is refused")
    func whenRestoring_thenThemeAndIconAreCarriedAndChecked() throws {
        defaults.removeObject(forKey: "appTheme")
        defaults.removeObject(forKey: "appIcon")
        defer {
            defaults.removeObject(forKey: "appTheme")
            defaults.removeObject(forKey: "appIcon")
        }

        try restore(["appTheme": "parmesan", "appIcon": "gold"])
        #expect(defaults.string(forKey: "appTheme") == "parmesan")
        #expect(defaults.string(forKey: "appIcon") == "gold")

        try restore(["appTheme": "neon", "appIcon": "../../etc"])
        #expect(defaults.string(forKey: "appTheme") == "parmesan")
        #expect(defaults.string(forKey: "appIcon") == "gold")
    }

    @Test("with nothing stored, a longer retention than the default passes and a shorter one is held back")
    func whenRetentionIsUnset_thenTheDefaultIsWhatItIsComparedWith() throws {
        defaults.removeObject(forKey: "retentionDays")
        defaults.removeObject(forKey: "retentionMaxItems")
        defer {
            defaults.removeObject(forKey: "retentionDays")
            defaults.removeObject(forKey: "retentionMaxItems")
        }

        let longer = try restore(["retentionDays": 60, "retentionMaxItems": 9000])
        #expect(longer.heldBack.isEmpty, "30 days and 5,000 clips are in force, so this keeps more")
        #expect(defaults.integer(forKey: "retentionDays") == 60)

        defaults.removeObject(forKey: "retentionDays")
        defaults.removeObject(forKey: "retentionMaxItems")
        let shorter = try restore(["retentionDays": 7, "retentionMaxItems": 500])
        #expect(Set(shorter.heldBack.map(\.key)) == ["retentionDays", "retentionMaxItems"])
    }

    @Test("numbers are clamped to what the setting allows, and values of the wrong type are ignored")
    func whenValuesAreOutOfRange_thenClampedOrIgnored() throws {
        defaults.set(30, forKey: "retentionDays")
        defaults.set(5000, forKey: "retentionMaxItems")
        defer {
            defaults.removeObject(forKey: "retentionDays")
            defaults.removeObject(forKey: "retentionMaxItems")
        }

        try restore(["retentionDays": -5, "retentionMaxItems": "lots"], approving: ["retentionDays"])
        #expect(defaults.integer(forKey: "retentionDays") == 1)
        #expect(defaults.integer(forKey: "retentionMaxItems") == 5000, "a string is not a number")

        try restore(["retentionDays": 999_999])
        #expect(defaults.integer(forKey: "retentionDays") == 365)

        try restore(["retentionDays": 0], approving: ["retentionDays"])
        #expect(defaults.integer(forKey: "retentionDays") == 0, "zero days is keep forever, not one day")
    }

    @Test("choices must be real choices, and good values are applied")
    func whenChoices_thenValidatedAndApplied() throws {
        defaults.set("dark", forKey: "appearanceMode")
        defer {
            for key in ["appearanceMode", "cardSize", "accentColorHex", "ruleTrimWhitespace"] {
                defaults.removeObject(forKey: key)
            }
        }

        try restore([
            "appearanceMode": "neon", "cardSize": "compact", "accentColorHex": "0A84FF", "ruleTrimWhitespace": true
        ])

        #expect(defaults.string(forKey: "appearanceMode") == "dark", "an unknown mode must be ignored")
        #expect(defaults.string(forKey: "cardSize") == "compact")
        #expect(defaults.string(forKey: "accentColorHex") == "0A84FF")
        #expect(defaults.bool(forKey: "ruleTrimWhitespace"))
    }

    @Test("an accent that is not a colour is ignored")
    func whenAccentIsGarbage_thenIgnored() throws {
        defaults.set("brand", forKey: "accentColorHex")
        defer { defaults.removeObject(forKey: "accentColorHex") }

        try restore(["accentColorHex": "<script>"])

        #expect(defaults.string(forKey: "accentColorHex") == "brand")
    }

    @Test("restoring puts the feedback and paste switches back, and re-registers the shortcuts")
    func whenRestoring_thenFeedbackKeysApplyAndHotkeysReregister() throws {
        let keys = ["soundEffectsEnabled", "pinnedWindowAutoPaste", "doubleCopyAppendEnabled"]
        defer { for key in keys {
            defaults.removeObject(forKey: key)
        } }
        let posted = NotificationCounter()
        let center = NotificationCenter()
        let token = center.addObserver(forName: .hotkeySettingsChanged, object: nil, queue: nil) { _ in
            posted.increment()
        }
        defer { center.removeObserver(token) }

        try restore(Dictionary(uniqueKeysWithValues: keys.map { ($0, true) }), notifying: center)

        for key in keys {
            #expect(defaults.bool(forKey: key), "\(key) should be restored")
        }
        #expect(posted.count == 1, "the global shortcuts only re-register when this is posted")
    }

    @Test("a value that would delete history or shorten retention is held back until the person approves it")
    func whenTheFileWouldDeleteData_thenItWaitsForApproval() throws {
        defaults.set(90, forKey: "retentionDays")
        defaults.set(5000, forKey: "retentionMaxItems")
        defaults.set(false, forKey: "clearOnQuit")
        defaults.set(false, forKey: "clearOnScreenLock")
        defer {
            for key in ["retentionDays", "retentionMaxItems", "clearOnQuit", "clearOnScreenLock"] {
                defaults.removeObject(forKey: key)
            }
        }
        let file: [String: Any] = [
            "retentionDays": 1, "retentionMaxItems": 100, "clearOnQuit": true, "clearOnScreenLock": true
        ]

        let held = try restore(file)

        #expect(Set(held.heldBack.map(\.key)) == [
            "retentionDays",
            "retentionMaxItems",
            "clearOnQuit",
            "clearOnScreenLock"
        ])
        #expect(defaults.integer(forKey: "retentionDays") == 90)
        #expect(defaults.integer(forKey: "retentionMaxItems") == 5000)
        #expect(!defaults.bool(forKey: "clearOnQuit") && !defaults.bool(forKey: "clearOnScreenLock"))

        let approved = try restore(file, approving: Set(held.heldBack.map(\.key)))

        #expect(approved.heldBack.isEmpty)
        #expect(defaults.integer(forKey: "retentionDays") == 1)
        #expect(defaults.integer(forKey: "retentionMaxItems") == 100)
        #expect(defaults.bool(forKey: "clearOnQuit") && defaults.bool(forKey: "clearOnScreenLock"))
    }

    @Test("values that keep more, or turn a clearing switch off, need no approval")
    func whenTheFileKeepsMore_thenItIsAppliedAtOnce() throws {
        defaults.set(30, forKey: "retentionDays")
        defaults.set(true, forKey: "clearOnQuit")
        defer {
            defaults.removeObject(forKey: "retentionDays")
            defaults.removeObject(forKey: "clearOnQuit")
        }

        let result = try restore(["retentionDays": 365, "clearOnQuit": false])

        #expect(result.heldBack.isEmpty)
        #expect(defaults.integer(forKey: "retentionDays") == 365)
        #expect(!defaults.bool(forKey: "clearOnQuit"))
    }

    @Test("a shortcut that would swallow Copy, or has no modifier, is not restored")
    func whenTheFileSetsAReservedShortcut_thenItIsIgnored() throws {
        let cmd = 256
        defaults.set(9, forKey: "overlayHotkeyKeyCode")
        defaults.set(cmd | 512, forKey: "overlayHotkeyModifiers")
        defaults.set(1, forKey: "pastePlainHotkeyKeyCode")
        defaults.set(cmd | 2048, forKey: "pastePlainHotkeyModifiers")
        defer {
            for key in [
                "overlayHotkeyKeyCode",
                "overlayHotkeyModifiers",
                "pastePlainHotkeyKeyCode",
                "pastePlainHotkeyModifiers"
            ] {
                defaults.removeObject(forKey: key)
            }
        }

        try restore([
            "overlayHotkeyKeyCode": 8, "overlayHotkeyModifiers": cmd,
            "pastePlainHotkeyKeyCode": 0, "pastePlainHotkeyModifiers": 0
        ])

        #expect(defaults.integer(forKey: "overlayHotkeyKeyCode") == 9, "Cmd-C must not become the shelf shortcut")
        #expect(defaults.integer(forKey: "overlayHotkeyModifiers") == cmd | 512)
        #expect(
            defaults.integer(forKey: "pastePlainHotkeyKeyCode") == 1,
            "a bare key is not a shortcut, and a shortcut with a default is not turned into nothing by it"
        )
        #expect(defaults.integer(forKey: "pastePlainHotkeyModifiers") == cmd | 2048)
    }

    @Test("a shortcut that has no default and is stored as unset comes back unset, which is a valid choice")
    func whenTheFileLeavesAnOptionalShortcutUnset_thenItIsRestoredUnset() throws {
        defaults.set(1, forKey: "quickPasteHotkeyKeyCode")
        defaults.set(256 | 2048, forKey: "quickPasteHotkeyModifiers")
        defer {
            defaults.removeObject(forKey: "quickPasteHotkeyKeyCode")
            defaults.removeObject(forKey: "quickPasteHotkeyModifiers")
        }

        try restore(["quickPasteHotkeyKeyCode": 0, "quickPasteHotkeyModifiers": 0])

        #expect(
            defaults.integer(forKey: "quickPasteHotkeyModifiers") == 0,
            "paste-previous has no default (ADR 0012)"
        )
    }

    @Test("a good shortcut pair is restored")
    func whenTheFileSetsAGoodShortcut_thenItIsApplied() throws {
        defer {
            defaults.removeObject(forKey: "pastePlainHotkeyKeyCode")
            defaults.removeObject(forKey: "pastePlainHotkeyModifiers")
        }

        try restore(["pastePlainHotkeyKeyCode": 9, "pastePlainHotkeyModifiers": 256 | 2048 | 4096])

        #expect(defaults.integer(forKey: "pastePlainHotkeyKeyCode") == 9)
        #expect(defaults.integer(forKey: "pastePlainHotkeyModifiers") == 256 | 2048 | 4096)
    }

    @Test("an optional shortcut is restored as a pair, and a file that gives it no modifier switches it off")
    func whenTheFileSetsAnOptionalShortcut_thenItIsAppliedOrCleared() throws {
        defer {
            defaults.removeObject(forKey: "toggleCaptureHotkeyKeyCode")
            defaults.removeObject(forKey: "toggleCaptureHotkeyModifiers")
        }

        try restore(["toggleCaptureHotkeyKeyCode": 35, "toggleCaptureHotkeyModifiers": 4096 | 2048])
        #expect(defaults.integer(forKey: "toggleCaptureHotkeyKeyCode") == 35)
        #expect(defaults.integer(forKey: "toggleCaptureHotkeyModifiers") == 4096 | 2048)

        try restore(["toggleCaptureHotkeyKeyCode": 0, "toggleCaptureHotkeyModifiers": 0])
        #expect(defaults.integer(forKey: "toggleCaptureHotkeyModifiers") == 0)
        #expect(GlobalShortcut.toggleCapture.binding(in: defaults) == nil)
    }

    @Test("the fingerprint changes with a setting a backup carries, and not with the backup's own bookkeeping")
    func whenOnlyBookkeepingChanges_thenTheFingerprintHolds() {
        let before = SettingsBackupManager.fingerprint(in: defaults)
        defer {
            defaults.removeObject(forKey: Setting.appTheme.name)
            defaults.removeObject(forKey: "autoBackupLastBackup")
        }

        defaults.set(Date.now, forKey: "autoBackupLastBackup")
        #expect(SettingsBackupManager.fingerprint(in: defaults) == before)

        defaults.set("mortar", forKey: Setting.appTheme.name)
        #expect(SettingsBackupManager.fingerprint(in: defaults) != before)
    }

    @Test("a backup from before the icons took their theme's name still restores its icon")
    func whenTheFileNamesAnOldIcon_thenItIsRestoredAsItsTheme() throws {
        defer { defaults.removeObject(forKey: Setting.appIcon.name) }

        try restore([Setting.appIcon.name: "gold"])

        #expect(AppIconChoice(stored: defaults.string(forKey: Setting.appIcon.name) ?? "") == .parmesan)
    }

    @Test("a shortcut the file says is turned off is turned off here")
    func whenTheFileTurnsAShortcutOff_thenItIsOff() throws {
        defer {
            defaults.removeObject(forKey: "pastePlainHotkeyKeyCode")
            defaults.removeObject(forKey: "pastePlainHotkeyModifiers")
        }

        try restore(["pastePlainHotkeyKeyCode": 0, "pastePlainHotkeyModifiers": -1])

        #expect(GlobalShortcut.pastePlainText.binding(in: defaults) == nil)
    }

    @Test("a bare key is not restored for an optional shortcut either")
    func whenTheFileGivesAnOptionalShortcutABareKey_thenItIsIgnored() throws {
        try restore(["toggleClipContentsHotkeyKeyCode": 35, "toggleClipContentsHotkeyModifiers": 512])

        #expect(GlobalShortcut.toggleClipContents.binding(in: defaults) == nil)
    }

    @Test("link previews are not part of a backup, and the Spotlight switch of an older version does not come back")
    func whenRestoring_thenSideEffectSwitchesAreLeftAlone() throws {
        defaults.set(false, forKey: "linkPreviewsEnabled")
        defaults.set(false, forKey: "spotlightIndexingEnabled")
        defer {
            defaults.removeObject(forKey: "linkPreviewsEnabled")
            defaults.removeObject(forKey: "spotlightIndexingEnabled")
        }

        try restore(["linkPreviewsEnabled": true, "spotlightIndexingEnabled": true])

        #expect(!defaults.bool(forKey: "linkPreviewsEnabled"))
        #expect(!defaults.bool(forKey: "spotlightIndexingEnabled"))
    }
}

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() {
        lock.withLock { value += 1 }
    }

    var count: Int {
        lock.withLock { value }
    }
}
