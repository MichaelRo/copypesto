// SPDX-License-Identifier: MIT
import Foundation

/// What the Paste One by One panel and its spoken progress tell the person to press: their own ⌘V when Pesto watches
/// for
/// it, otherwise whatever is bound to Open the shelf (which advances the stack), not a key that may have been rebound.
public enum StackHint {
    public static func text(pastesWithCommandV: Bool, openShelf: HotkeyBinding?) -> String {
        if pastesWithCommandV { return String(localized: "⌘V pastes the next") }
        guard let openShelf else { return String(localized: "Open the shelf to paste") }
        let keys = HotkeyDescription.string(keyCode: UInt32(openShelf.keyCode), modifiers: openShelf.modifiers)
        return String(localized: "\(keys) to paste")
    }
}
