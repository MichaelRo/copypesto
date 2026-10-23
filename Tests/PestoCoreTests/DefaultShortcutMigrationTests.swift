// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Foundation
import Testing
@testable import PestoCore

@Suite("The paste-previous shortcut is no longer bound by default")
struct DefaultShortcutMigrationTests {
    private let optionCommand = HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: UInt32(cmdKey | optionKey))

    private func binding(_ defaults: UserDefaults) -> HotkeyBinding? {
        GlobalShortcut.pastePrevious.binding(in: defaults)
    }

    @Test("a fresh install starts with no paste-previous shortcut")
    func whenFreshInstall_thenUnset() {
        let defaults = ThrowawayDefaults.make()

        DefaultShortcutMigration.run(defaults: defaults)

        #expect(binding(defaults) == nil)
        #expect(GlobalShortcut.pastePrevious.defaultBinding == nil)
    }

    @Test("a Mac that is already set up keeps the shortcut it has been using")
    func whenAlreadyOnboarded_thenCommandOptionVIsKeptAsTheirOwnChoice() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.hasOnboarded)

        DefaultShortcutMigration.run(defaults: defaults)

        #expect(binding(defaults) == optionCommand)
    }

    @Test("a shortcut the person turned off or changed is left alone")
    func whenPersonChoseSomethingElse_thenNotTouched() {
        let off = ThrowawayDefaults.make()
        off.set(true, for: Setting.hasOnboarded)
        off.set(GlobalShortcut.disabledMarker, for: GlobalShortcut.pastePrevious.modifiersSetting)
        DefaultShortcutMigration.run(defaults: off)
        #expect(binding(off) == nil)

        let custom = ThrowawayDefaults.make()
        custom.set(true, for: Setting.hasOnboarded)
        custom.set(kVK_ANSI_P, for: GlobalShortcut.pastePrevious.keyCodeSetting)
        custom.set(controlKey | optionKey, for: GlobalShortcut.pastePrevious.modifiersSetting)
        DefaultShortcutMigration.run(defaults: custom)
        #expect(binding(custom) == HotkeyBinding(keyCode: kVK_ANSI_P, modifiers: UInt32(controlKey | optionKey)))
    }

    @Test("it runs once: a shortcut turned back to its default later is not rewritten")
    func whenRunTwice_thenTheSecondRunDoesNothing() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.hasOnboarded)
        DefaultShortcutMigration.run(defaults: defaults)
        defaults.set(0, for: GlobalShortcut.pastePrevious.modifiersSetting)

        DefaultShortcutMigration.run(defaults: defaults)

        #expect(binding(defaults) == nil)
    }
}
