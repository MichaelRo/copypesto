// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Foundation

/// The shortcuts macOS itself has switched on (Spotlight, screenshots, Mission Control, input sources and the rest of
/// System Settings → Keyboard → Keyboard Shortcuts). A Carbon hotkey that matches one of them registers without an
/// error and then never fires, because the system takes the key first, so a recorder asks before it accepts one.
public enum SystemShortcuts {
    private static let carried = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    public static func enabledBindings() -> [HotkeyBinding] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let entries = array?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return nil }
            return HotkeyBinding(keyCode: code, modifiers: UInt32(truncatingIfNeeded: modifiers))
        }
    }

    /// True when `binding` is one of `list`, comparing the key and the four modifiers (the system's own entries also
    /// carry flags such as Fn, which a Pesto shortcut cannot).
    public static func conflicts(_ binding: HotkeyBinding, in list: [HotkeyBinding]) -> Bool {
        let wanted = binding.modifiers & carried
        return wanted != 0 && list.contains { $0.keyCode == binding.keyCode && $0.modifiers & carried == wanted }
    }
}
