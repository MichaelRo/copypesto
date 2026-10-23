// SPDX-License-Identifier: MIT
import Carbon.HIToolbox

public enum HotkeyDescription {
    public static func string(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyName(for: keyCode)
    }

    /// The same combination in words, for VoiceOver and anything else that would read the symbols as drawings:
    /// "Control Option Shift Command V".
    public static func spoken(keyCode: UInt32, modifiers: UInt32) -> String {
        var words: [String] = []
        if modifiers & UInt32(controlKey) != 0 { words.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { words.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { words.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { words.append("Command") }
        let spokenKeys = [
            "⌫": "Delete", "Esc": "Escape", "←": "Left Arrow", "→": "Right Arrow", "↑": "Up Arrow", "↓": "Down Arrow"
        ]
        let name = keyName(for: keyCode)
        words.append(spokenKeys[name] ?? name)
        return words.joined(separator: " ")
    }

    /// The shelf shortcut as stored; zero modifiers means "never customised", like when it is registered.
    public static func overlay(storedKeyCode: Int, storedModifiers: Int) -> String {
        guard let binding = GlobalShortcut.openShelf.binding(
            storedKeyCode: storedKeyCode,
            storedModifiers: storedModifiers
        ) else { return "" }
        return string(keyCode: UInt32(binding.keyCode), modifiers: binding.modifiers)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_Space): "Space", UInt32(kVK_Tab): "Tab", UInt32(kVK_Return): "Return",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_Escape): "Esc",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓"
        ]
        return map[keyCode] ?? "?"
    }
}
