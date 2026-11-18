// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The chip row, and what choosing a chip filters")
struct LibraryFilterTests {
    private let trip = UUID()
    private let work = UUID()

    @Test("at rest the row is All, Pinned, each collection and New Collection, with no kinds")
    func whenNotSearching_thenScopesAndCollections() {
        let chips = LibraryChip.row(collectionIDs: [trip, work], isSearching: false)
        #expect(chips == [.all, .pinned, .collection(trip), .collection(work), .newCollection])
    }

    @Test("while searching the row offers the six kinds after a divider, and no New Collection")
    func whenSearching_thenKindsFollowADivider() {
        let chips = LibraryChip.row(collectionIDs: [trip], isSearching: true)
        let kinds = LibraryScope.filteredKinds.map(LibraryChip.kind)
        #expect(chips == [.all, .pinned, .collection(trip), .divider] + kinds)
    }

    @Test("a scope chip replaces the scope; a kind chip toggles on top of it")
    func whenChipsAreChosen_thenTheFilterFollows() {
        var filter = LibraryFilter()
        #expect(filter.isSelected(.all))
        filter.choose(.collection(trip))
        #expect(filter.scope == .collection(trip))
        #expect(!filter.isSelected(.all))
        filter.choose(.kind(.url))
        #expect(filter.kind == .url)
        #expect(filter.scope == .collection(trip))
        filter.choose(.kind(.url))
        #expect(filter.kind == nil)
        filter.choose(.kind(.image))
        filter.choose(.kind(.color))
        #expect(filter.kind == .color)
    }

    @Test("ending a search drops the kind but keeps the scope")
    func whenSearchEnds_thenKindClears() {
        var filter = LibraryFilter(scope: .pinned, kind: .code)
        filter.endSearch()
        #expect(filter == LibraryFilter(scope: .pinned, kind: nil))
    }

    @Test("a deleted collection sends the library back to All")
    func whenTheChosenCollectionIsGone_thenAll() {
        var filter = LibraryFilter(scope: .collection(trip))
        filter.forget(collections: [work])
        #expect(filter.scope == .all)
        filter = LibraryFilter(scope: .collection(work))
        filter.forget(collections: [work])
        #expect(filter.scope == .collection(work))
    }

    @Test("the chip row stands in for the sidebar wherever the sidebar is not on screen")
    func whenTheSidebarIsHidden_thenTheChipRowShows() {
        #expect(LibraryChrome.showsChipRow(isRegular: false, columns: .all))
        #expect(LibraryChrome.showsChipRow(isRegular: true, columns: .detailOnly))
        #expect(!LibraryChrome.showsChipRow(isRegular: true, columns: .all))
        #expect(!LibraryChrome.showsChipRow(isRegular: true, columns: .doubleColumn))
    }
}
