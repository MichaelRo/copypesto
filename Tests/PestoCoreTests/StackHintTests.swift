// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Testing
@testable import PestoCore

@Suite("Paste One by One hint")
struct StackHintTests {
    private let shelf = HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: UInt32(cmdKey | shiftKey))

    @Test("with Accessibility the hint names the person's own ⌘V")
    func whenWatching_thenCommandV() {
        #expect(StackHint.text(pastesWithCommandV: true, openShelf: shelf) == "⌘V pastes the next")
    }

    @Test("without it the hint names the key that is bound to Open the shelf, whatever it is")
    func whenNotWatching_thenTheBoundKey() {
        #expect(StackHint.text(pastesWithCommandV: false, openShelf: shelf) == "⇧⌘V to paste")
        let rebound = HotkeyBinding(keyCode: kVK_ANSI_B, modifiers: UInt32(controlKey | optionKey))
        #expect(StackHint.text(pastesWithCommandV: false, openShelf: rebound) == "⌃⌥B to paste")
    }

    @Test("with the shelf shortcut turned off the hint says to open the shelf, not a key that does nothing")
    func whenShelfShortcutOff_thenNoKey() {
        #expect(StackHint.text(pastesWithCommandV: false, openShelf: nil) == "Open the shelf to paste")
    }
}
