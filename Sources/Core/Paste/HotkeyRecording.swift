// SPDX-License-Identifier: MIT
import Carbon.HIToolbox

/// What a combination typed into a shortcut recorder amounts to.
public enum HotkeyRecordingOutcome: Equatable, Sendable {
    case accepted
    /// Nothing but Shift, or no modifier at all.
    case needsModifier
    /// Command with a key every app uses (C, V, Q, Tab...).
    case reservedBySystem
    /// Another Pesto shortcut has it; the name says which.
    case clash(String)
    /// macOS has switched on a system shortcut for it, which would take the key before Pesto sees it.
    case takenBySystem
}

public enum HotkeyRecording {
    static let pinnedSlotsName = "Pinned clip shortcuts"

    private static let digitKeyCodes: Set<Int> = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]
    private static let carriedMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    public static func evaluate(
        keyCode: Int, modifiers: UInt32, others: [NamedHotkey], system: [HotkeyBinding] = []
    )
    -> HotkeyRecordingOutcome {
        let carried = modifiers & carriedMask
        guard carried & UInt32(cmdKey | optionKey | controlKey) != 0 else { return .needsModifier }
        guard HotkeyPolicy.isAcceptable(keyCode: keyCode, modifiers: modifiers) else { return .reservedBySystem }
        if let other = others.first(where: { $0.keyCode == keyCode && $0.modifiers & carriedMask == carried }) {
            return .clash(other.name)
        }
        if carried == UInt32(controlKey), digitKeyCodes.contains(keyCode) { return .clash(pinnedSlotsName) }
        if SystemShortcuts.conflicts(HotkeyBinding(keyCode: keyCode, modifiers: modifiers), in: system) {
            return .takenBySystem
        }
        return .accepted
    }
}
