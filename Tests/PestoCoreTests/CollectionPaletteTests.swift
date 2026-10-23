// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("CollectionPalette")
struct CollectionPaletteTests {
    @Test("the first collection gets the first colour")
    func whenNoneUsed_thenFirst() {
        #expect(CollectionPalette.nextUnused(used: []) == CollectionPalette.colors[0])
    }

    @Test("a new collection takes the first colour no collection uses, whatever the case or hash")
    func whenSomeUsed_thenFirstFree() {
        let used = ["#" + CollectionPalette.colors[0].lowercased(), CollectionPalette.colors[1]]
        #expect(CollectionPalette.nextUnused(used: used) == CollectionPalette.colors[2])
    }

    @Test("when every colour is used the palette starts again, by how many collections there are")
    func whenAllUsed_thenCycles() {
        let used = CollectionPalette.colors + [CollectionPalette.colors[0]]
        #expect(CollectionPalette.nextUnused(used: used) == CollectionPalette.colors[1])
    }

    @Test("two spellings of one colour are the same colour")
    func whenSpelledDifferently_thenSame() {
        #expect(CollectionPalette.isSame("#34c759", "34C759"))
        #expect(!CollectionPalette.isSame("34C759", "FF3B30"))
    }

    @Test("a colour outside the palette is custom")
    func whenOutsidePalette_thenCustom() {
        #expect(CollectionPalette.isCustom("#123456"))
        #expect(!CollectionPalette.isCustom(CollectionPalette.colors[3]))
    }
}
