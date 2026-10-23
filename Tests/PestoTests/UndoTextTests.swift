// SPDX-License-Identifier: MIT
import PestoCore
import Testing
@testable import Pesto

@Suite("The words for Undo and Redo")
struct UndoTextTests {
    private let labels: [UndoLabel] = [
        .deleteClips(1), .deleteClips(3), .deleteCollection("Work"), .createCollection("Work"),
        .editCollection("Work"), .duplicateCollection("Work copy"), .reorderCollections, .importCollection("Work"),
        .addClips(.snippet, 1), .addClips(.snippet, 4), .addClips(.imported, 2), .editSnippet,
        .changeClip(.title), .changeClip(.note), .changeClip(.tags), .changeClip(.icon), .changeClip(.collection),
        .changeClip(.pinned), .changeClip(.shortcut), .changeClip(.sensitive), .changeClip(.expiry),
        .changeClip(.order)
    ]

    @Test("every kind of action has a sentence, a menu title and a spoken result")
    func whenAnyLabel_thenEveryTextIsFilledIn() {
        for label in labels {
            #expect(!UndoText.action(label).isEmpty, "\(label)")
            #expect(UndoText.menuTitle(undo: label).hasPrefix("Undo "), "\(label)")
            #expect(UndoText.menuTitle(redo: label).hasPrefix("Redo "), "\(label)")
            #expect(!UndoText.done(UndoOutcome(label: label, direction: .undone)).isEmpty, "\(label)")
        }
    }

    @Test("a collection's name is in what is said about it")
    func whenACollectionChanged_thenItsNameIsSpoken() {
        #expect(UndoText.action(.createCollection("Work")).contains("Work"))
        #expect(UndoText.menuTitle(undo: .deleteCollection("Work")).contains("Work"))
    }

    @Test("with nothing to undo the menu says only Undo")
    func whenNothingToUndo_thenPlainTitles() {
        #expect(UndoText.menuTitle(undo: nil) == "Undo")
        #expect(UndoText.menuTitle(redo: nil) == "Redo")
    }
}
