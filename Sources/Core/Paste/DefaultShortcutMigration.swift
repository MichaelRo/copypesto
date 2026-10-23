// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Foundation

/// Paste the previous clip stopped being bound by default (ADR 0012). A person who has already set Pesto up keeps the
/// ⌥⌘V they have been using: it is written once as their own choice, so only a fresh install starts without it.
public enum DefaultShortcutMigration {
    public static let doneKey = "defaultShortcutsMigrated"

    public static func run(defaults: UserDefaults = AppDefaults.store) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard defaults.value(for: Setting.hasOnboarded),
              defaults.value(for: GlobalShortcut.pastePrevious.modifiersSetting) == 0 else { return }
        defaults.set(kVK_ANSI_V, for: GlobalShortcut.pastePrevious.keyCodeSetting)
        defaults.set(cmdKey | optionKey, for: GlobalShortcut.pastePrevious.modifiersSetting)
    }
}
