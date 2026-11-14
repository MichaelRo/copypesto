// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("Library actions go through Core's undoable paths")
@MainActor
struct MobileLibraryActionsTests {
    @Test("a delete offers Undo, and Undo brings the clip back")
    func whenDeleted_thenUndoRestores() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("delete me")
        let id = item.id

        await library.state.delete([id])
        try await library.refreshed()
        #expect(library.store.item(for: id) == nil)
        #expect(library.state.undoOffer == .deleteClips(1))

        await library.state.undo()
        try await library.refreshed()
        #expect(library.store.items.contains { $0.id == id })
        #expect(library.state.undoOffer == nil)
    }

    @Test("a picture added from iOS is judged after it is saved, and then its row is no longer covered")
    func whenAPictureIsAdded_thenItIsUncoveredOnceJudged() async throws {
        let library = try await MobileTestLibrary()
        let size = CGSize(width: 40, height: 30)
        let png = UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        #expect(await library.state.add(ClipCapture.picture(png, typeIdentifier: UTType.png.identifier)))
        let item = try await library.settle()

        #expect(item.type == .image)
        #expect(!item.analysisPending)
        #expect(!library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isConcealed)
    }

    @Test("a copy too large for one clip is refused, and the refusal is shown")
    func whenTooLarge_thenTheRefusalIsShown() async throws {
        let library = try await MobileTestLibrary()
        let huge = String(repeating: "a", count: ClipSizePolicy.maxTextBytes + 1)

        let added = await library.state.add(ClipCapture.text(huge))

        #expect(!added)
        #expect(library.state.notice?.isProblem == true)
        #expect(library.state.notice?.text.isEmpty == false)
    }

    @Test("Clear History keeps pinned clips and empties Undo")
    func whenCleared_thenPinnedStayAndUndoIsEmpty() async throws {
        let library = try await MobileTestLibrary()
        let pinned = try await library.add("keep me")
        let pinnedID = pinned.id
        await library.state.togglePin(pinnedID)
        let loose = try await library.add("lose me")
        await library.state.delete([loose.id])
        _ = try await library.add("lose me too")
        #expect(library.state.undoHistory?.undoLabel != nil)

        await library.state.clearHistory()
        try await library.refreshed()

        #expect(library.store.items.map(\.id) == [pinnedID])
        #expect(library.state.undoHistory?.undoLabel == nil)
        #expect(library.state.undoOffer == nil)
    }

    @Test("Copy writes the clip and moves it to the front of the history")
    func whenCopied_thenItIsInFront() async throws {
        let library = try await MobileTestLibrary()
        let first = try await library.add("first clip")
        _ = try await library.add("second clip")
        #expect(library.store.items.first?.id != first.id)

        #expect(library.state.copy(first))
        try await library.refreshed()

        #expect(library.store.items.first?.id == first.id)
        #expect(AppPasteboard.general.string == "first clip")
        #expect(library.state.notice?.isProblem == false)
    }

    @Test("an edit of the title, note and tags is saved, sealed and undoable")
    func whenDetailsAreEdited_thenTheEditIsUndoable() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("an untitled clip")
        var edited = ClipDetailsDraft(title: " Trip ", note: "", tags: [])
        edited.tags = "travel, #Travel, , work"
        let context = try #require(item.modelContext)

        library.state.clipEditor(context: context).edit(item) { clip in
            clip.customTitle = edited.cleanTitle
            clip.userNote = edited.cleanNote
            clip.tags = edited.cleanTags
        }

        #expect(item.customTitle == "Trip")
        #expect(item.userNote == nil)
        #expect(item.tags == ["travel", "work"])
        #expect(item.legacyCustomTitle == nil)
        #expect(library.state.undoHistory?.undoLabel != nil)
    }
}
