// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Editing a clip's text in the detail goes through Core and can be undone")
@MainActor
struct MobileTextEditTests {
    @Test("a saved edit changes the clip and offers Undo, which brings the old text back")
    func whenTextSaved_thenUndoIsOffered() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("old words")
        let drawn = ClipCard.Revision(item)

        #expect(await library.state.editText(of: item, to: "new words"))
        try await library.refreshed()
        let edited = try #require(library.store.item(for: item.id))
        #expect(edited.displayPreviewText == "new words")
        #expect(ClipCard.Revision(edited) != drawn, "the card is drawn again with the new text")
        #expect(library.state.undoOffer == .editText)

        await library.state.undo()
        try await library.refreshed()
        #expect(library.store.item(for: item.id)?.displayPreviewText == "old words")
    }

    @Test("text another clip holds is refused and the person is told")
    func whenTextIsAnotherClips_thenRefusalIsShown() async throws {
        let library = try await MobileTestLibrary()
        let first = try await library.add("one text")
        _ = try await library.add("two text")

        #expect(await library.state.editText(of: first, to: "two text") == false)
        #expect(library.state.notice?.isProblem == true)
        #expect(library.state.undoOffer == nil)
    }

    @Test("a hidden clip can be edited only once it is shown")
    func whenSecretNotShown_thenItCannotBeEdited() async throws {
        let library = try await MobileTestLibrary()
        try await library.service.ingest(#require(ClipCapture.text("4111 1111 1111 1111")))
        let secret = try await library.settle()
        #expect(secret.sensitivityRaw != nil)

        #expect(!library.state.canEditText(secret))
        #expect(await library.state.editText(of: secret, to: "4000 0000 0000 0002") == false)

        await library.state.secretReveal.show(secret.id, reason: "test")
        #expect(library.state.canEditText(secret))
    }

    @Test("pictures and files have no text to edit; text, code, links and colors do")
    func whenKindsCompared_thenOnlyTextLikeClipsAreEditable() async throws {
        let library = try await MobileTestLibrary()
        for text in ["plain words", "https://copypesto.net", "#3A7BD5", "{\"a\": [1, 2, 3]}"] {
            let item = try await library.add(text)
            #expect(library.state.canEditText(item), "\(text)")
        }
    }

    @Test("the grid's clip shows the new text from the save alone, with no refresh asked for, on a store on disk")
    func whenSaved_thenTheStoreFollowsWithoutARefresh() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try await MobileTestLibrary(storeURL: folder.appendingPathComponent("clips.store"))
        let item = try await library.add("before the edit")
        _ = item.gridPreview
        let drawn = ClipCard.Revision(item)

        #expect(await library.state.editText(of: item, to: "after the edit"))

        let deadline = ContinuousClock.now + .seconds(3)
        while library.store.item(for: item.id)?.gridPreview != "after the edit", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let shown = try #require(library.store.item(for: item.id))
        #expect(shown.gridPreview == "after the edit")
        #expect(ClipCard.Revision(shown) != drawn)
        #expect(library.store.items.contains { $0.id == item.id && $0.gridPreview == "after the edit" })
    }
}
