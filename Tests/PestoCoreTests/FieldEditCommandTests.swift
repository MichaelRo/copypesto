// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Edit commands in the search field")
struct FieldEditCommandTests {
    @Test("the character decides, as a menu item's key equivalent does")
    func whenCharacterGiven_thenItDecides() {
        #expect(FieldEditCommand.resolve(characters: "x", keyCode: 7, shift: false) == .cut)
        #expect(FieldEditCommand.resolve(characters: "c", keyCode: 8, shift: false) == .copy)
        #expect(FieldEditCommand.resolve(characters: "v", keyCode: 9, shift: false) == .paste)
        #expect(FieldEditCommand.resolve(characters: "z", keyCode: 6, shift: false) == .undo)
        #expect(
            FieldEditCommand.resolve(characters: "v", keyCode: 2, shift: false) == .paste,
            "Dvorak: V sits on the D key"
        )
    }

    @Test("without a character the US key code answers")
    func whenNoCharacter_thenKeyCodeAnswers() {
        #expect(FieldEditCommand.resolve(characters: nil, keyCode: 7, shift: false) == .cut)
        #expect(FieldEditCommand.resolve(characters: "", keyCode: 9, shift: false) == .paste)
    }

    @Test("shift turns undo into redo and cancels cut, copy and paste")
    func whenShift_thenOnlyUndoSurvivesAsRedo() {
        #expect(FieldEditCommand.resolve(characters: "z", keyCode: 6, shift: true) == .redo)
        #expect(FieldEditCommand.resolve(characters: "x", keyCode: 7, shift: true) == nil)
        #expect(FieldEditCommand.resolve(characters: "c", keyCode: 8, shift: true) == nil)
        #expect(FieldEditCommand.resolve(characters: "v", keyCode: 9, shift: true) == nil)
    }

    @Test("other keys are not Edit commands")
    func whenOtherKey_thenNil() {
        #expect(FieldEditCommand.resolve(characters: "a", keyCode: 0, shift: false) == nil)
    }
}
