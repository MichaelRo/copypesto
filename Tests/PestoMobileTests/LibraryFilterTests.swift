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

    @Test("while searching the row offers the six kinds, Today, This Week and Other Devices, and no New Collection")
    func whenSearching_thenKindsAndDatesFollowDividers() {
        let chips = LibraryChip.row(collectionIDs: [trip], isSearching: true)
        let kinds = LibraryScope.filteredKinds.map(LibraryChip.kind)
        #expect(chips == [.all, .pinned, .collection(trip), .divider] + kinds
            + [.divider, .date(.today), .date(.week), .otherDevices])
    }

    @Test("date and Other Devices chips toggle on top of the scope and end with the search")
    func whenDateAndDeviceChipsAreChosen_thenTheyToggle() {
        var filter = LibraryFilter(scope: .pinned)
        filter.choose(.date(.today))
        filter.choose(.otherDevices)
        #expect(filter.date == .today)
        #expect(filter.otherDevicesOnly)
        #expect(filter.isSelected(.date(.today)) && filter.isSelected(.otherDevices))
        filter.choose(.date(.week))
        #expect(filter.date == .week)
        filter.choose(.date(.week))
        #expect(filter.date == nil)
        filter.endSearch()
        #expect(!filter.otherDevicesOnly)
        #expect(filter.scope == .pinned)
    }

    @Test("Today starts at midnight and This Week seven days back, as the Mac's date chips do")
    func whenDateChips_thenTheMacsCutoffs() throws {
        let noon = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))
        var filter = LibraryFilter()
        #expect(filter.dateCutoff(now: noon) == nil)
        filter.date = .today
        #expect(filter.dateCutoff(now: noon) == Calendar.current.startOfDay(for: noon))
        filter.date = .week
        #expect(filter.dateCutoff(now: noon) == noon.addingTimeInterval(-7 * 86_400))
    }

    @MainActor
    @Test("the criteria built keep clips by age and by arrival from another device")
    func whenChipsAreOn_thenTheIndexIsNarrowed() async throws {
        let library = try await MobileTestLibrary()
        try await library.add("made here")
        let remote = PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data("made elsewhere".utf8),
            payloadString: "made elsewhere", contentHash: ClipCapture.hash(of: Data("made elsewhere".utf8)),
            isRemote: true
        )
        try await library.service.ingest(remote)
        try await library.refreshed()
        let index = try #require(library.store.searchIndex())
        let remoteID = try #require(library.store.items.first { $0.displayPreviewText == "made elsewhere" }?.id)

        let all = LibraryScope.all.ids(in: index, query: "")
        let today = LibraryScope.all.ids(in: index, query: "", dateCutoff: LibraryFilter(date: .today).dateCutoff())
        let future = LibraryScope.all.ids(
            in: index, query: "", dateCutoff: LibraryFilter(date: .week).dateCutoff(now: .now.addingTimeInterval(30 * 86_400))
        )
        let others = LibraryScope.all.ids(in: index, query: "", otherDevicesOnly: true)

        #expect(all.count == 2)
        #expect(Set(today) == Set(all))
        #expect(future.isEmpty)
        #expect(others == [remoteID])
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
