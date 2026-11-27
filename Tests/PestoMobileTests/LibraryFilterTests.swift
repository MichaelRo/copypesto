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

    @Test("while searching the row offers the six kinds, When, Sensitive and Other Devices, and no New Collection")
    func whenSearching_thenKindsAndDatesFollowDividers() {
        let chips = LibraryChip.row(collectionIDs: [trip], isSearching: true)
        let kinds = LibraryScope.filteredKinds.map(LibraryChip.kind)
        #expect(chips == [.all, .pinned, .collection(trip), .scopeDivider] + kinds
            + [.filterDivider, .when, .sensitive, .otherDevices])

        let withFrom = LibraryChip.row(
            collectionIDs: [trip], isSearching: true, showsScopes: false, showsFrom: true
        )
        #expect(withFrom == kinds + [.filterDivider, .when, .from, .sensitive, .otherDevices])
    }

    @Test("When, Sensitive and Other Devices chips work on top of the scope and end with the search")
    func whenDateAndDeviceChipsAreChosen_thenTheyToggle() {
        var filter = LibraryFilter(scope: .pinned)
        filter.chooseDate(.today)
        filter.choose(.sensitive)
        filter.choose(.otherDevices)
        #expect(filter.dateFilter == .today)
        #expect(filter.sensitiveOnly)
        #expect(filter.otherDevicesOnly)
        #expect(filter.isSelected(.when) && filter.isSelected(.sensitive) && filter.isSelected(.otherDevices))
        filter.chooseDate(.week)
        #expect(filter.dateFilter == .week)
        filter.chooseDate(.all)
        #expect(filter.dateFilter == .all)
        filter.endSearch()
        #expect(!filter.sensitiveOnly)
        #expect(!filter.otherDevicesOnly)
        #expect(filter.scope == .pinned)
    }

    @Test("Today starts at midnight, This Week seven days back, and customRange wraps a single day or range")
    func whenDateChips_thenTheMacsCutoffs() throws {
        let noon = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))
        var filter = LibraryFilter()
        #expect(filter.dateCutoff(now: noon) == nil)
        filter.dateFilter = .today
        #expect(filter.dateCutoff(now: noon) == Calendar.current.startOfDay(for: noon))
        filter.dateFilter = .week
        #expect(filter.dateCutoff(now: noon) == noon.addingTimeInterval(-7 * 86_400))

        let nov10 = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15)))
        let nov12 = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9)))
        filter.dateFilter = SearchDateFilter.customRange(from: nov12, to: nov10)
        let window = filter.dateWindow(now: noon)
        #expect(window.cutoff == Calendar.current.startOfDay(for: nov10))
        #expect(window.before == Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: nov12)
        ))
    }

    @MainActor
    @Test("the criteria built keep clips by age, source app, sensitivity and arrival from another device")
    func whenChipsAreOn_thenTheIndexIsNarrowed() async throws {
        let library = try await MobileTestLibrary()
        try await library.service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data("from notes".utf8),
            payloadString: "from notes", frontmostBundleID: "com.apple.Notes",
            contentHash: ClipCapture.hash(of: Data("from notes".utf8))
        ))
        let remote = PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data("made elsewhere".utf8),
            payloadString: "made elsewhere", contentHash: ClipCapture.hash(of: Data("made elsewhere".utf8)),
            isRemote: true
        )
        try await library.service.ingest(remote)
        try await library.refreshed()
        let index = try #require(library.store.searchIndex())
        let remoteID = try #require(library.store.items.first { $0.displayPreviewText == "made elsewhere" }?.id)
        let notesID = try #require(library.store.items.first { $0.displayPreviewText == "from notes" }?.id)

        let all = LibraryScope.all.ids(in: index, query: "")
        let today = LibraryScope.all.ids(
            in: index,
            query: "",
            dateCutoff: LibraryFilter(dateFilter: .today).dateCutoff()
        )
        let future = LibraryScope.all.ids(
            in: index, query: "",
            dateCutoff: LibraryFilter(dateFilter: .week).dateCutoff(now: .now.addingTimeInterval(30 * 86_400))
        )
        let others = LibraryScope.all.ids(in: index, query: "", otherDevicesOnly: true)
        let byApp = LibraryScope.all.ids(in: index, query: "", sourceBundleID: "com.apple.Notes")

        #expect(all.count == 2)
        #expect(Set(today) == Set(all))
        #expect(future.isEmpty)
        #expect(others == [remoteID])
        #expect(byApp == [notesID])
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

    @Test("the chip row stands in for the sidebar when hidden, and opens on iPad while searching")
    func whenTheSidebarIsHidden_thenTheChipRowShows() {
        #expect(LibraryChrome.showsChipRow(isRegular: false, columns: .all))
        #expect(LibraryChrome.showsChipRow(isRegular: true, columns: .detailOnly))
        #expect(!LibraryChrome.showsChipRow(isRegular: true, columns: .all))
        #expect(!LibraryChrome.showsChipRow(isRegular: true, columns: .doubleColumn))
        #expect(LibraryChrome.showsChipRow(isRegular: true, columns: .all, isSearching: true))
    }

    @Test("on compact iPhone while searching, scopes stay on row 1 and search filters move to row 2")
    func whenCompactSearchingWithScopes_thenFiltersSplitToSecondRow() {
        let kinds = LibraryScope.filteredKinds.map(LibraryChip.kind)
        let split = LibraryChip.rows(
            collectionIDs: [trip, work],
            isSearching: true,
            offersAsk: true,
            showsScopes: true,
            showsFrom: true,
            splitsSearchFilters: true
        )
        #expect(split.count == 2)
        #expect(split[0] == [.all, .pinned, .collection(trip), .collection(work)])
        #expect(split[1] == [.ask] + kinds + [.filterDivider, .when, .from, .sensitive, .otherDevices])

        let atRest = LibraryChip.rows(
            collectionIDs: [trip], isSearching: false, showsScopes: true, splitsSearchFilters: true
        )
        #expect(atRest == [[.all, .pinned, .collection(trip), .newCollection]])

        let ipadSidebarVisible = LibraryChip.rows(
            collectionIDs: [trip], isSearching: true, showsScopes: false, splitsSearchFilters: false
        )
        #expect(ipadSidebarVisible == [kinds + [.filterDivider, .when, .sensitive, .otherDevices]])

        let ipadCompactOrSingleRow = LibraryChip.rows(
            collectionIDs: [trip], isSearching: true, showsScopes: true, splitsSearchFilters: false
        )
        #expect(ipadCompactOrSingleRow.count == 1)
    }
}
