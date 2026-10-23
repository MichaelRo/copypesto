// SPDX-License-Identifier: MIT
import Foundation

/// Exports and restores Pesto's `UserDefaults`-backed settings to/from JSON.
///
/// A settings file can come from anyone, so every value is checked against what its setting accepts. The history
/// lock, the screen-sharing blur and the exclusion list are deliberately not part of a backup at all: a file must not
/// be able to switch off a protection, so those stay as each Mac has them. Device-specific values (window frame,
/// onboarding) are also left out, and so are the link-preview and Spotlight switches: turning either on has side
/// effects (network fetches, indexing) that a plain value restore would skip or bypass.
public enum SettingsBackupManager {
    private enum Rule {
        case bool
        case integer(ClosedRange<Int>)
        /// A range, and one value outside it that means something of its own (zero days: keep forever).
        case integerOrSpecial(ClosedRange<Int>, special: Int)
        case choice(Set<String>)
        case accent
    }

    /// A modifier mask, or `GlobalShortcut.disabledMarker` for a shortcut that was turned off.
    private static let modifierRange = GlobalShortcut.disabledMarker...Int(UInt32.max)

    private static let rules: [String: Rule] = [
        Setting.retentionDays.name: .integerOrSpecial(1...365, special: RetentionChoices.foreverDays),
        Setting.retentionMaxItems.name: .integer(100...10_000),
        Setting.clearOnScreenLock.name: .bool,
        Setting.clearOnQuit.name: .bool,
        Setting.appleIntelligenceEnabled.name: .bool,
        Setting.accentColorHex.name: .accent,
        Setting.appTheme.name: .choice(Set(AppTheme.allCases.map(\.rawValue))),
        Setting.appThemeDark.name: .choice(Set(AppTheme.allCases.map(\.rawValue) + [""])),
        Setting.appIcon.name: .choice(AppIconChoice.acceptedStoredValues),
        Setting.appearanceMode.name: .choice(Set(AppearanceMode.allCases.map(\.rawValue))),
        Setting.cardSize.name: .choice(Set(CardSize.allCases.map(\.rawValue))),
        Setting.shelfPosition.name: .choice(Set(ShelfPosition.allCases.map(\.rawValue))),
        Setting.cardWidth.name: .integerOrSpecial(CardMetrics.widthRange, special: 0),
        Setting.nsfwMode.name: .choice(Set(NSFWMode.allCases.map(\.rawValue))),
        Setting.ruleStripTracking.name: .bool,
        Setting.ruleTrimWhitespace.name: .bool,
        Setting.ruleNormalizeLineEndings.name: .bool,
        Setting.ruleRemoveDuplicateSpaces.name: .bool,
        Setting.overlayHotkeyKeyCode.name: .integer(0...127),
        Setting.overlayHotkeyModifiers.name: .integer(modifierRange),
        Setting.quickPasteHotkeyKeyCode.name: .integer(0...127),
        Setting.quickPasteHotkeyModifiers.name: .integer(modifierRange),
        Setting.pastePlainHotkeyKeyCode.name: .integer(0...127),
        Setting.pastePlainHotkeyModifiers.name: .integer(modifierRange),
        Setting.togglePinnedWindowHotkeyKeyCode.name: .integer(0...127),
        Setting.togglePinnedWindowHotkeyModifiers.name: .integer(modifierRange),
        Setting.toggleCaptureHotkeyKeyCode.name: .integer(0...127),
        Setting.toggleCaptureHotkeyModifiers.name: .integer(modifierRange),
        Setting.toggleClipContentsHotkeyKeyCode.name: .integer(0...127),
        Setting.toggleClipContentsHotkeyModifiers.name: .integer(modifierRange),
        Setting.soundEffects.name: .bool,
        Setting.showMenuBarIcon.name: .bool,
        Setting.pinnedWindowAutoPaste.name: .bool,
        Setting.opensQuickMenuAtCursor.name: .bool,
        Setting.doubleCopyAppend.name: .bool
    ]

    public static var backupKeys: [String] {
        rules.keys.sorted()
    }

    /// A string that changes exactly when a setting a backup carries changes, so a change to one can be noticed
    /// without exporting.
    public static func fingerprint(in defaults: UserDefaults = AppDefaults.store) -> String {
        backupKeys.map { key in "\(key)=\(defaults.object(forKey: key).map { String(describing: $0) } ?? "")" }
            .joined(separator: "\n")
    }

    public static func export(from defaults: UserDefaults = AppDefaults.store) throws -> Data {
        var dict: [String: Any] = [:]
        for key in backupKeys {
            if let value = defaults.object(forKey: key) {
                dict[key] = value
            }
        }
        let payload: [String: Any] = ["version": 1, "settings": dict]
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public struct HeldBack: Equatable, Sendable {
        public let key: String
        public let description: String

        public init(key: String, description: String) {
            self.key = key
            self.description = description
        }
    }

    public struct RestoreResult: Equatable, Sendable {
        public let applied: Int
        /// Changes that delete history or keep less of it: applied only when the person approves them (`approving`).
        public let heldBack: [HeldBack]

        public init(applied: Int, heldBack: [HeldBack]) {
            self.applied = applied
            self.heldBack = heldBack
        }
    }

    public static func restore(
        from data: Data, approving: Set<String> = [], into defaults: UserDefaults = AppDefaults.store,
        notifying center: NotificationCenter = .default
    ) throws
    -> RestoreResult {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = payload["settings"] as? [String: Any] else
        {
            throw CocoaError(.fileReadCorruptFile)
        }
        let hotkeyKeys = Set(GlobalShortcut.allCases.flatMap {
            [$0.keyCodeSetting.name, $0.modifiersSetting.name]
        })
        var applied = 0
        var heldBack: [HeldBack] = []
        for (key, rule) in rules where !hotkeyKeys.contains(key) {
            guard let raw = settings[key], let value = checked(raw, against: rule) else { continue }
            if !approving.contains(key), let description = deletionDescription(key: key, new: value, in: defaults) {
                heldBack.append(HeldBack(key: key, description: description))
                continue
            }
            defaults.set(value, forKey: key)
            applied += 1
        }
        for shortcut in GlobalShortcut.allCases {
            applied += restoreHotkey(shortcut, from: settings, into: defaults)
        }
        center.post(name: .hotkeySettingsChanged, object: nil)
        return RestoreResult(applied: applied, heldBack: heldBack.sorted { $0.key < $1.key })
    }

    /// A shortcut is only restored as a whole pair and only if Pesto would accept it: a file must not be able to
    /// register Command-C, or a bare key, as a global shortcut. A shortcut that starts unset can also be cleared by a
    /// file that says it has no modifiers.
    private static func restoreHotkey(
        _ shortcut: GlobalShortcut, from settings: [String: Any], into defaults: UserDefaults
    )
    -> Int {
        let codeKey = shortcut.keyCodeSetting.name
        let modifierKey = shortcut.modifiersSetting.name
        guard let codeRule = rules[codeKey], let modifierRule = rules[modifierKey] else { return 0 }
        let code = settings[codeKey].flatMap { checked($0, against: codeRule) } as? Int
        let modifiers = settings[modifierKey].flatMap { checked($0, against: modifierRule) } as? Int
        guard code != nil || modifiers != nil else { return 0 }
        if modifiers == GlobalShortcut.disabledMarker || (shortcut.isOptional && modifiers == 0) {
            defaults.set(0, forKey: codeKey)
            defaults.set(modifiers, forKey: modifierKey)
            return 1
        }
        let current = defaults.object(forKey: codeKey) as? Int
        guard let newCode = code ?? current ?? shortcut.defaultBinding?.keyCode else { return 0 }
        let newModifiers = modifiers ?? defaults.integer(forKey: modifierKey)
        guard HotkeyPolicy.isAcceptable(keyCode: newCode, modifiers: UInt32(newModifiers)) else { return 0 }
        defaults.set(newCode, forKey: codeKey)
        defaults.set(newModifiers, forKey: modifierKey)
        return 1
    }

    /// Words for a restored value that deletes history or keeps less of it than this Mac does now, else nil.
    private static func deletionDescription(key: String, new: Any, in defaults: UserDefaults) -> String? {
        switch key {
        case Setting.clearOnQuit.name where new as? Bool == true && !defaults.bool(forKey: key):
            return String(localized: "Clear history when Pesto quits")
        case Setting.clearOnScreenLock.name where new as? Bool == true && !defaults.bool(forKey: key):
            return String(localized: "Clear history when the screen locks")
        case Setting.retentionDays.name:
            guard let days = new as? Int, days != RetentionChoices.foreverDays else { return nil }
            let current = defaults.value(for: Setting.retentionDays)
            guard current == RetentionChoices.foreverDays || days < current else { return nil }
            return String(localized: "Delete clips older than \(days) days")
        case Setting.retentionMaxItems.name:
            guard let count = new as? Int else { return nil }
            let current = defaults.value(for: Setting.retentionMaxItems)
            guard current <= 0 || count < current else { return nil }
            return String(localized: "Keep only the newest \(count) clips")
        default:
            return nil
        }
    }

    private static func checked(_ value: Any, against rule: Rule) -> Any? {
        switch rule {
        case .bool:
            return (value as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil }
        case let .integer(range):
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return min(max(number.intValue, range.lowerBound), range.upperBound)
        case let .integerOrSpecial(range, special):
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.intValue == special ? special : min(max(number.intValue, range.lowerBound), range.upperBound)
        case let .choice(allowed):
            return (value as? String).flatMap { allowed.contains($0) ? $0 : nil }
        case .accent:
            guard let text = value as? String else { return nil }
            return AccentChoice(stored: text) == .brand && text != "brand" ? nil : text
        }
    }
}
