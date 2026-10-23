// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Shelf command keys follow the character, not the key position")
struct ShelfCommandTests {
    @Test("on a US keyboard the character and the key code agree")
    func whenUS_thenCommandsResolve() {
        #expect(ShelfCommand.resolve(characters: "f", keyCode: 3) == .search)
        #expect(ShelfCommand.resolve(characters: "[", keyCode: 33) == .previousCollection)
        #expect(ShelfCommand.resolve(characters: "]", keyCode: 30) == .nextCollection)
        #expect(ShelfCommand.resolve(characters: ",", keyCode: 43) == .settings)
        #expect(ShelfCommand.resolve(characters: "n", keyCode: 45) == .newCollection)
        #expect(ShelfCommand.resolve(characters: "p", keyCode: 35) == .pasteAll)
        #expect(ShelfCommand.resolve(characters: "k", keyCode: 40) == .actions)
        #expect(ShelfCommand.resolve(characters: "s", keyCode: 1) == .saveImage)
        #expect(ShelfCommand.resolve(characters: "a", keyCode: 0) == .selectAll)
        #expect(ShelfCommand.resolve(characters: "y", keyCode: 16) == .quickLook)
        #expect(ShelfCommand.resolve(characters: "e", keyCode: 14) == .showHidden)
    }

    @Test("⌘C copies the focused clip, on any layout that prints C and by key position when nothing prints")
    func whenC_thenCopy() {
        #expect(ShelfCommand.resolve(characters: "c", keyCode: 8) == .copy)
        #expect(ShelfCommand.resolve(characters: "C", keyCode: 8) == .copy)
        #expect(ShelfCommand.resolve(characters: nil, keyCode: 8) == .copy)
        #expect(ShelfCommand.resolve(characters: "c", keyCode: 8, shift: true) == .copy)
    }

    @Test("Quick Look is the key that prints Y on a German keyboard, where Y and Z swap places")
    func whenQWERTZ_thenTheKeyPrintingYIsQuickLook() {
        #expect(ShelfCommand.resolve(characters: "y", keyCode: 6) == .quickLook)
        #expect(ShelfCommand.resolve(characters: "z", keyCode: 16) == .undo)
    }

    @Test("on AZERTY the key labeled A, which has key code 12, selects all, and the key at position 0 does not")
    func whenAZERTY_thenTheLabelWins() {
        #expect(ShelfCommand.resolve(characters: "a", keyCode: 12) == .selectAll)
        #expect(ShelfCommand.resolve(characters: "q", keyCode: 0) == nil)
    }

    @Test("on Dvorak the letter on the key decides, wherever the key sits")
    func whenDvorak_thenTheLetterWins() {
        #expect(ShelfCommand.resolve(characters: "k", keyCode: 7) == .actions)
        #expect(ShelfCommand.resolve(characters: "n", keyCode: 38) == .newCollection)
        #expect(ShelfCommand.resolve(characters: "p", keyCode: 15) == .pasteAll)
        #expect(ShelfCommand.resolve(characters: "f", keyCode: 17) == .search)
    }

    @Test("on QWERTZ the key at code 33, which prints Ü, is not the collection key")
    func whenQWERTZ_thenUmlautIsNothing() {
        #expect(ShelfCommand.resolve(characters: "ü", keyCode: 33) == nil)
    }

    @Test("when the system gives no character, the US key position is used")
    func whenNoCharacter_thenKeyPosition() {
        #expect(ShelfCommand.resolve(characters: "", keyCode: 40) == .actions)
        #expect(ShelfCommand.resolve(characters: nil, keyCode: 0) == .selectAll)
    }

    @Test("the number keys paste by position and Return keeps its own meaning")
    func whenDigitsOrReturn_thenByKeyCode() {
        #expect(ShelfCommand.resolve(characters: "&", keyCode: 18) == .pasteNth(1))
        #expect(ShelfCommand.resolve(characters: "9", keyCode: 25) == .pasteNth(9))
        #expect(ShelfCommand.resolve(characters: "\r", keyCode: 36) == .returnKey)
    }

    @Test("Shift turns Paste All into Paste One by One, and no other command changes with it")
    func whenShift_thenPasteOneByOne() {
        #expect(ShelfCommand.resolve(characters: "p", keyCode: 35, shift: true) == .pasteOneByOne)
        #expect(ShelfCommand.resolve(characters: "p", keyCode: 35, shift: false) == .pasteAll)
        #expect(ShelfCommand.resolve(characters: "p", keyCode: 15, shift: true) == .pasteOneByOne)
        #expect(ShelfCommand.resolve(characters: nil, keyCode: 35, shift: true) == .pasteOneByOne)
        #expect(ShelfCommand.resolve(characters: "a", keyCode: 0, shift: true) == .selectAll)
    }

    @Test("⌘Z undoes and Shift turns it into redo, on the key that prints Z")
    func whenZ_thenUndoAndShiftRedo() {
        #expect(ShelfCommand.resolve(characters: "z", keyCode: 6) == .undo)
        #expect(ShelfCommand.resolve(characters: "z", keyCode: 6, shift: true) == .redo)
        #expect(ShelfCommand.resolve(characters: "y", keyCode: 6) == .quickLook)
    }

    @Test("M no longer merges: Paste All replaced it")
    func whenM_thenNothing() {
        #expect(ShelfCommand.resolve(characters: "m", keyCode: 46) == nil)
    }
}
