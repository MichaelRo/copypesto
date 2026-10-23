// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Foundation

public struct HotkeyBinding: Equatable, Sendable {
    public let keyCode: Int
    public let modifiers: UInt32

    public init(keyCode: Int, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// The shortcuts Pesto registers system-wide, with what each is called, where it is stored and what it starts as.
/// The recorder, the registration and the settings export all read this list, so a shortcut is spelled once.
///
/// Stored as a key code and a modifier mask. A mask of zero means "never changed": the default, or none for the
/// shortcuts that start unset. A mask of `disabledMarker` means the person turned off a shortcut that has a default.
/// Every recorded combination carries a modifier, so neither can be a real one; the key code is not tested, because
/// zero is the A key.
public enum GlobalShortcut: CaseIterable, Sendable {
    case openShelf
    case pastePrevious
    case pastePlainText
    case togglePinnedWindow
    case toggleCapture
    case toggleClipContents

    public var label: String {
        switch self {
        case .openShelf: "Open the shelf"
        case .pastePrevious: "Paste the previous clip"
        case .pastePlainText: "Paste as plain text"
        case .togglePinnedWindow: "Show or hide the floating window"
        case .toggleCapture: "Pause or resume capturing"
        case .toggleClipContents: "Hide or show clip contents"
        }
    }

    public var keyCodeSetting: SettingKey<Int> {
        switch self {
        case .openShelf: Setting.overlayHotkeyKeyCode
        case .pastePrevious: Setting.quickPasteHotkeyKeyCode
        case .pastePlainText: Setting.pastePlainHotkeyKeyCode
        case .togglePinnedWindow: Setting.togglePinnedWindowHotkeyKeyCode
        case .toggleCapture: Setting.toggleCaptureHotkeyKeyCode
        case .toggleClipContents: Setting.toggleClipContentsHotkeyKeyCode
        }
    }

    public var modifiersSetting: SettingKey<Int> {
        switch self {
        case .openShelf: Setting.overlayHotkeyModifiers
        case .pastePrevious: Setting.quickPasteHotkeyModifiers
        case .pastePlainText: Setting.pastePlainHotkeyModifiers
        case .togglePinnedWindow: Setting.togglePinnedWindowHotkeyModifiers
        case .toggleCapture: Setting.toggleCaptureHotkeyModifiers
        case .toggleClipContents: Setting.toggleClipContentsHotkeyModifiers
        }
    }

    /// Nil for a shortcut that is off until the person records one.
    public var defaultBinding: HotkeyBinding? {
        switch self {
        case .openShelf: HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: UInt32(cmdKey | shiftKey))
        case .pastePlainText: HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: UInt32(controlKey | optionKey | cmdKey))
        case .pastePrevious, .togglePinnedWindow, .toggleCapture, .toggleClipContents: nil
        }
    }

    public var isOptional: Bool {
        defaultBinding == nil
    }

    /// Unique within the process; 3 to 11 belong to the nine pinned-clip slots.
    public var carbonID: UInt32 {
        switch self {
        case .openShelf: 1
        case .pastePrevious: 2
        case .pastePlainText: 12
        case .togglePinnedWindow: 13
        case .toggleCapture: 14
        case .toggleClipContents: 15
        }
    }

    public static let disabledMarker = -1

    public func binding(storedKeyCode: Int, storedModifiers: Int) -> HotkeyBinding? {
        guard storedModifiers != Self.disabledMarker else { return nil }
        guard storedModifiers != 0 else { return defaultBinding }
        return HotkeyBinding(keyCode: storedKeyCode, modifiers: UInt32(truncatingIfNeeded: storedModifiers))
    }

    public func binding(in defaults: UserDefaults) -> HotkeyBinding? {
        binding(
            storedKeyCode: defaults.value(for: keyCodeSetting),
            storedModifiers: defaults.value(for: modifiersSetting)
        )
    }

    /// The other shortcuts that are set, which a new combination for this one may not duplicate.
    public func others(in defaults: UserDefaults) -> [NamedHotkey] {
        Self.allCases.filter { $0 != self }.compactMap { other in
            other.binding(in: defaults).map {
                NamedHotkey(name: other.label, keyCode: $0.keyCode, modifiers: $0.modifiers)
            }
        }
    }
}

public extension Notification.Name {
    /// Posted after a shortcut is recorded, reset, turned off or restored from a settings file, so the registered
    /// hotkeys follow it.
    static let hotkeySettingsChanged = AppIdentity.notificationName("hotkeySettingsChanged")
}
