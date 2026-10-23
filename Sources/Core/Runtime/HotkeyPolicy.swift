// SPDX-License-Identifier: MIT
import Carbon.HIToolbox

/// Which global shortcuts Pesto will register. Applied to a settings file restored from outside, where a shortcut such
/// as Command-C would otherwise swallow Copy system wide.
public enum HotkeyPolicy {
    private static let reservedWithCommandAlone: Set<Int> = [
        kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_A, kVK_ANSI_Z, kVK_ANSI_Q, kVK_ANSI_W,
        kVK_Tab, kVK_Space, kVK_ANSI_H, kVK_ANSI_M
    ]

    public static func isAcceptable(keyCode: Int, modifiers: UInt32) -> Bool {
        guard (0...127).contains(keyCode) else { return false }
        let carried = modifiers & UInt32(cmdKey | optionKey | controlKey | shiftKey)
        guard carried & UInt32(cmdKey | optionKey | controlKey) != 0 else { return false }
        if carried == UInt32(cmdKey), reservedWithCommandAlone.contains(keyCode) { return false }
        return true
    }
}
