// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What the Clip Inspector saves for a title, a note and tags")
struct ClipDetailsEditTests {
    @Test("a title or note of only spaces is no title or note, and the rest keeps its text")
    func whenBlank_thenNil() {
        #expect(ClipDetailsEdit.title("   ") == nil)
        #expect(ClipDetailsEdit.title("  Mom's arrival ") == "Mom's arrival")
        #expect(ClipDetailsEdit.note("\n\n") == nil)
        #expect(ClipDetailsEdit.note("Ask about the cheese.\n") == "Ask about the cheese.")
    }

    @Test("a typed tag is added once, without its @ or spaces, and a tag is removed by name in any case")
    func whenTagging_thenNormalized() {
        #expect(ClipDetailsEdit.adding("@Travel ", to: ["genoa"]) == ["genoa", "Travel"])
        #expect(ClipDetailsEdit.adding("travel", to: ["Travel"]) == ["Travel"])
        #expect(ClipDetailsEdit.adding("#work, @home", to: []) == ["work", "home"], "iOS types # and the Mac @")
        #expect(ClipDetailsEdit.adding("  ", to: ["a"]) == ["a"])
        #expect(ClipDetailsEdit.adding("work, trip", to: []) == ["work", "trip"])
        #expect(ClipDetailsEdit.removing("TRAVEL", from: ["Travel", "genoa"]) == ["genoa"])
    }

    @Test("⌘I shows the focused clip's details")
    func whenCommandI_thenShowDetails() {
        #expect(ShelfCommand.resolve(characters: "i", keyCode: 34) == .showDetails)
    }
}
