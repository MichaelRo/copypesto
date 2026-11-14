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

    @Test("a draft edited in place saves only when its cleaned text differs from the clip's")
    func whenDraftIsCompared_thenOnlyRealChangesCount() {
        var draft = ClipDetailsDraft(title: "Old", note: nil, tags: ["a"])
        #expect(!draft.differs(title: "Old", note: nil, tags: ["a"]))
        draft.title = "  Old  "
        draft.note = "   "
        draft.tags = "a, "
        #expect(!draft.differs(title: "Old", note: nil, tags: ["a"]))
        draft.note = "New note"
        #expect(draft.differs(title: "Old", note: nil, tags: ["a"]))
    }

    @Test("a card speaks as one element: kind, content, source, age and pin")
    func whenACardIsSpoken_thenOneSentenceSaysItAll() {
        let label = CardSpeech.label(
            kind: "Link", summary: "copypesto.net", source: "Safari", age: "4 minutes ago", isPinned: true
        )
        #expect(label == "Link, copypesto.net, Safari, 4 minutes ago, Pinned")
        let bare = CardSpeech.label(kind: "Text", summary: "Hidden clip", source: nil, age: "just now", isPinned: false)
        #expect(bare == "Text, Hidden clip, just now")
    }

    @Test("copying a hidden secret puts the real text on the clipboard and leaves it masked")
    func whenACoveredSecretIsCopied_thenItIsNotShown() async throws {
        let library = try await MobileTestLibrary()
        try await library.service.ingest(#require(ClipCapture.text("ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i")))
        let secret = try await library.settle()
        #expect(library.state.secretReveal.concealment(for: secret).isConcealed)
        #expect(library.state.copy(secret))
        #expect(!library.state.secretReveal.isShown(secret.id))
        #expect(library.state.secretReveal.concealment(for: secret).isConcealed)
    }
}
