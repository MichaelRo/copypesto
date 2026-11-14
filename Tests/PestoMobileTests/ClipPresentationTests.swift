// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("What a row and the detail view say about a clip")
@MainActor
struct ClipPresentationTests {
    private let open = CardConcealment(screenShareBlur: false, sensitiveBlur: false)

    @Test("a link names its host, a color carries its swatch, and a title replaces the preview")
    func whenSummarized_thenEachKindSaysItsOwnThing() async throws {
        let library = try await MobileTestLibrary()
        let link = try await library.add("https://www.apple.com/ipad/")
        let color = try await library.add("#3F7D4E")
        let note = try await library.add("a note with a title")
        let context = try #require(note.modelContext)
        library.state.clipEditor(context: context).edit(note) { $0.customTitle = "Named" }

        let linkSummary = ClipSummary.make(link, concealment: open)
        #expect(linkSummary.title.contains("apple.com"))
        let colorSummary = ClipSummary.make(color, concealment: open)
        guard case .swatch = colorSummary.visual else {
            Issue.record("a color clip shows a swatch, got \(colorSummary.visual)")
            return
        }
        let noteSummary = ClipSummary.make(note, concealment: open)
        #expect(noteSummary.title == "Named")
        #expect(noteSummary.detail == "a note with a title")
    }

    @Test("the facts are Core's, in words: when, how long, and the color's channels")
    func whenFactsAreWorded_thenTheyReadAsSentences() async throws {
        let library = try await MobileTestLibrary()
        let color = try await library.add("#3F7D4E")
        let facts = ClipFacts.facts(for: color, collectionName: "Brand", isShown: true)

        #expect(facts.contains(.rgb(red: 63, green: 125, blue: 78)))
        #expect(facts.contains(.collection("Brand")))
        #expect(ClipFacts.text(for: .characters(1)) == "1 character")
        #expect(ClipFacts.text(for: .characters(12)) == "12 characters")
        #expect(ClipFacts.text(for: .rgb(red: 1, green: 2, blue: 3)) == "RGB 1, 2, 3")
    }

    @Test("the Undo banner names what was deleted, counted properly")
    func whenDeleted_thenTheBannerCountsClips() {
        #expect(UndoOfferText.action(.deleteClips(1)) == "Deleted 1 clip")
        #expect(UndoOfferText.action(.deleteClips(3)) == "Deleted 3 clips")
    }

    @Test("an empty title or note clears it, and tags are trimmed and kept once")
    func whenDraftIsCleaned_thenEmptyFieldsClear() {
        var draft = ClipDetailsDraft(title: "Old", note: "Kept", tags: ["a", "b"])
        #expect(draft.tags == "a, b")
        draft.title = "   "
        draft.tags = "#x, X, y ,"
        #expect(draft.cleanTitle == nil)
        #expect(draft.cleanNote == "Kept")
        #expect(draft.cleanTags == ["x", "y"])
    }
}
