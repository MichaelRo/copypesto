// SPDX-License-Identifier: MIT
import AppKit

/// A paste stack is pasted by the person's own ⌘V in whatever app they are in: after each paste Pesto puts the next
/// clip on the pasteboard and watches for the keystroke that pastes it (ADR 0009). This is the judgement of one
/// keystroke: is it that ⌘V, and not the one Pesto posts itself to paste the first clip.
public enum StackKeyPolicy {
    public static func isUserPaste(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, pasteKeyCode: UInt16, ownPasteInFlight: Bool
    )
    -> Bool {
        guard !ownPasteInFlight, keyCode == pasteKeyCode else { return false }
        return modifiers.intersection([.command, .shift, .option, .control]) == .command
    }
}
