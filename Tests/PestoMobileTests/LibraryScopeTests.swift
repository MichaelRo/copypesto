// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The library's scopes and search")
@MainActor
struct LibraryScopeTests {
    @Test("all clips come newest first, and the search text narrows them on the history index")
    func whenSearching_thenOnlyMatchingClipsShow() async throws {
        let library = try await MobileTestLibrary()
        let older = try await library.add("packing list for the trip")
        let newer = try await library.add("grocery list")
        let index = try #require(library.store.searchIndex())

        #expect(LibraryScope.all.ids(in: index, query: "") == [newer.id, older.id])
        #expect(LibraryScope.all.ids(in: index, query: "  PACKING ") == [older.id])
        #expect(LibraryScope.all.ids(in: index, query: "nothing like it").isEmpty)
    }

    @Test("a kind narrows the scope to clips of that kind, and Pinned shows only pinned clips")
    func whenScoped_thenOnlyThatKindOrPinnedShows() async throws {
        let library = try await MobileTestLibrary()
        let link = try await library.add("https://www.apple.com/ipad/")
        let note = try await library.add("a plain note")
        await library.state.togglePin(note.id)
        try await library.refreshed()
        let index = try #require(library.store.searchIndex())

        #expect(LibraryScope.all.ids(in: index, query: "", kind: .url) == [link.id])
        #expect(LibraryScope.all.ids(in: index, query: "", kind: .image).isEmpty)
        #expect(LibraryScope.pinned.ids(in: index, query: "") == [note.id])
        #expect(LibraryScope.pinned.ids(in: index, query: "", kind: .url).isEmpty)
    }

    @Test("a collection shows the clips moved into it")
    func whenACollectionIsChosen_thenItsClipsShow() async throws {
        let library = try await MobileTestLibrary()
        let kept = try await library.add("in the collection")
        _ = try await library.add("left outside")
        let board = try #require(library.state.addCollection(named: "Trip", existing: []))
        library.state.moveToCollection(kept, collectionID: board.id)
        let index = try #require(library.store.searchIndex())

        #expect(LibraryScope.collection(board.id).ids(in: index, query: "") == [kept.id])
    }

    @Test("a locked collection's clips leave All and search, and show on its chip only once opened (ADR 0081)")
    func whenACollectionIsLocked_thenItsClipsShowOnlyOnItsOpenedChip() async throws {
        let library = try await MobileTestLibrary()
        let hidden = try await library.add("salad secret")
        let free = try await library.add("salad recipe")
        let board = try #require(library.state.addCollection(named: "Vault", existing: []))
        library.state.moveToCollection(hidden, collectionID: board.id)
        let index = try #require(library.store.searchIndex())
        let closed = CollectionLock(locked: [board.id])
        let opened = CollectionLock(locked: [board.id], opened: [board.id])

        #expect(LibraryScope.all.ids(in: index, query: "", collectionLock: opened) == [free.id])
        #expect(LibraryScope.all.ids(in: index, query: "salad", collectionLock: opened) == [free.id])
        #expect(LibraryScope.collection(board.id).ids(in: index, query: "", collectionLock: closed).isEmpty)
        #expect(LibraryScope.collection(board.id).ids(in: index, query: "", collectionLock: opened) == [hidden.id])
    }

    @Test("the kinds the library filters by are the six kinds of clip")
    func whenListingKinds_thenEveryKindIsThere() {
        #expect(Set(LibraryScope.filteredKinds) == Set(ClipboardType.allCases))
    }
}
