// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("StackKeyPolicy: which keystroke moves a paste stack on")
struct StackKeyPolicyTests {
    private let vKey: UInt16 = 9

    @Test("a plain ⌘V is the person pasting the clip that was made ready")
    func whenCommandV_thenItIsAUserPaste() {
        #expect(StackKeyPolicy.isUserPaste(
            keyCode: vKey,
            modifiers: .command,
            pasteKeyCode: vKey,
            ownPasteInFlight: false
        ))
    }

    @Test("⌘V on another layout is found by the key code that layout gives V")
    func whenLayoutMovesV_thenThatKeyCounts() {
        #expect(StackKeyPolicy.isUserPaste(keyCode: 40, modifiers: .command, pasteKeyCode: 40, ownPasteInFlight: false))
        #expect(!StackKeyPolicy.isUserPaste(keyCode: 9, modifiers: .command, pasteKeyCode: 40, ownPasteInFlight: false))
    }

    @Test("a different key, or ⌘V with another modifier, is not a plain paste")
    func whenOtherKeysOrModifiers_thenNotAUserPaste() {
        #expect(!StackKeyPolicy.isUserPaste(
            keyCode: 8,
            modifiers: .command,
            pasteKeyCode: vKey,
            ownPasteInFlight: false
        ))
        #expect(!StackKeyPolicy.isUserPaste(keyCode: vKey, modifiers: [], pasteKeyCode: vKey, ownPasteInFlight: false))
        #expect(!StackKeyPolicy.isUserPaste(
            keyCode: vKey,
            modifiers: [.command, .shift],
            pasteKeyCode: vKey,
            ownPasteInFlight: false
        ))
        #expect(!StackKeyPolicy.isUserPaste(
            keyCode: vKey,
            modifiers: [.command, .option],
            pasteKeyCode: vKey,
            ownPasteInFlight: false
        ))
    }

    @Test("the ⌘V Pesto posts itself to paste the first clip is never counted as the person's")
    func whenOwnPasteIsInFlight_thenIgnored() {
        #expect(!StackKeyPolicy.isUserPaste(
            keyCode: vKey,
            modifiers: .command,
            pasteKeyCode: vKey,
            ownPasteInFlight: true
        ))
    }

    @Test("caps lock and function-key bits do not hide a plain ⌘V")
    func whenIncidentalModifierBits_thenStillAUserPaste() {
        #expect(StackKeyPolicy.isUserPaste(
            keyCode: vKey, modifiers: [.command, .capsLock], pasteKeyCode: vKey, ownPasteInFlight: false
        ))
    }
}
