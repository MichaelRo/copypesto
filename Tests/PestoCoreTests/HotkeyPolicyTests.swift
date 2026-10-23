// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Testing
@testable import PestoCore

@Suite("Which shortcuts Pesto accepts")
struct HotkeyPolicyTests {
    private let command = UInt32(cmdKey)
    private let shift = UInt32(shiftKey)
    private let option = UInt32(optionKey)
    private let control = UInt32(controlKey)

    @Test("a shortcut needs a modifier other than Shift")
    func needsAModifier() {
        #expect(!HotkeyPolicy.isAcceptable(keyCode: 9, modifiers: 0))
        #expect(!HotkeyPolicy.isAcceptable(keyCode: 9, modifiers: shift))
        #expect(HotkeyPolicy.isAcceptable(keyCode: 9, modifiers: control))
    }

    @Test("Command alone with a system editing or window key is reserved")
    func reservedSystemShortcuts() {
        for key in [8, 9, 7, 0, 6, 12, 13, 48, 49, 4, 46] { // C V X A Z Q W Tab Space H M
            #expect(!HotkeyPolicy.isAcceptable(keyCode: key, modifiers: command), "⌘\(key)")
        }
    }

    @Test("the same keys with another modifier added are fine, as the defaults are")
    func combinationsAreFine() {
        #expect(HotkeyPolicy.isAcceptable(keyCode: 9, modifiers: command | shift))
        #expect(HotkeyPolicy.isAcceptable(keyCode: 9, modifiers: control | option | command))
        #expect(HotkeyPolicy.isAcceptable(keyCode: 8, modifiers: command | option))
    }

    @Test("key codes outside the keyboard are refused")
    func keyCodeRange() {
        #expect(!HotkeyPolicy.isAcceptable(keyCode: -1, modifiers: control))
        #expect(!HotkeyPolicy.isAcceptable(keyCode: 200, modifiers: control))
    }
}
