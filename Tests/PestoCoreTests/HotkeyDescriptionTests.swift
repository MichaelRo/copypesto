// SPDX-License-Identifier: MIT
import Carbon.HIToolbox
import Testing
@testable import PestoCore

@Suite("HotkeyDescription")
struct HotkeyDescriptionTests {
    @Test("the default overlay shortcut reads ⇧⌘V")
    func whenDefaultOverlay_thenShiftCommandV() {
        let text = HotkeyDescription.string(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))

        #expect(text == "⇧⌘V")
    }

    @Test("modifiers are ordered control, option, shift, command")
    func whenAllModifiers_thenCanonicalOrder() {
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)

        #expect(HotkeyDescription.string(keyCode: UInt32(kVK_Space), modifiers: all) == "⌃⌥⇧⌘Space")
    }

    @Test("an unknown key code shows a question mark rather than nothing")
    func whenUnknownKey_thenQuestionMark() {
        #expect(HotkeyDescription.string(keyCode: 9999, modifiers: UInt32(cmdKey)) == "⌘?")
    }

    @Test("stored zero values fall back to the defaults")
    func whenNothingStored_thenDefaultOverlayShortcut() {
        #expect(HotkeyDescription.overlay(storedKeyCode: 0, storedModifiers: 0) == "⇧⌘V")
    }

    @Test("a stored custom shortcut is described as stored")
    func whenCustomStored_thenDescribed() {
        let text = HotkeyDescription.overlay(storedKeyCode: Int(kVK_ANSI_K), storedModifiers: cmdKey | optionKey)

        #expect(text == "⌥⌘K")
    }

    @Test("a shortcut is spoken in words, in the order it is drawn")
    func whenSpoken_thenWords() {
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)

        #expect(HotkeyDescription
            .spoken(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) == "Shift Command V")
        #expect(HotkeyDescription
            .spoken(keyCode: UInt32(kVK_Space), modifiers: all) == "Control Option Shift Command Space")
    }

    @Test("keys drawn as a symbol are spoken as their names")
    func whenSymbolKey_thenName() {
        #expect(HotkeyDescription.spoken(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey)) == "Command Delete")
        #expect(HotkeyDescription
            .spoken(keyCode: UInt32(kVK_Escape), modifiers: UInt32(controlKey)) == "Control Escape")
        #expect(HotkeyDescription
            .spoken(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey)) == "Option Left Arrow")
    }

    @Test("a letter shortcut becomes a lowercase key with its modifiers, for a menu item to show")
    func whenLetterShortcut_thenMenuKeyEquivalent() throws {
        let all = UInt32(controlKey | optionKey | cmdKey)
        let equivalent = try #require(HotkeyDescription.menuKeyEquivalent(keyCode: UInt32(kVK_ANSI_V), modifiers: all))
        #expect(equivalent.character == "v")
        #expect(equivalent.control && equivalent.option && equivalent.command)
        #expect(!equivalent.shift)
    }

    @Test("a digit shortcut is a menu key too, and shift is kept")
    func whenDigitShortcut_thenMenuKeyEquivalent() throws {
        let equivalent = try #require(HotkeyDescription.menuKeyEquivalent(
            keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(shiftKey | cmdKey)
        ))
        #expect(equivalent.character == "7")
        #expect(equivalent.shift && equivalent.command)
    }

    @Test("keys a menu cannot draw as one character have no menu equivalent")
    func whenNamedOrUnknownKey_thenNil() {
        for code in [kVK_Space, kVK_F5, kVK_LeftArrow, kVK_Delete] {
            #expect(HotkeyDescription.menuKeyEquivalent(keyCode: UInt32(code), modifiers: UInt32(cmdKey)) == nil)
        }
        #expect(HotkeyDescription.menuKeyEquivalent(keyCode: 9999, modifiers: UInt32(cmdKey)) == nil)
    }
}
