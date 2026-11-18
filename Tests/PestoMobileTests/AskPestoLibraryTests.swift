// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Ask Pesto in the library's search")
struct AskPestoLibraryTests {
    private let trip = UUID()

    @Test("the Ask chip leads the filters once words are typed, and gives way to what it found")
    func whenWordsAreTyped_thenAskIsOffered() {
        let plain = LibraryChip.row(collectionIDs: [trip], isSearching: true)
        #expect(!plain.contains(.ask) && !plain.contains(.asked))
        let typed = LibraryChip.row(collectionIDs: [trip], isSearching: true, offersAsk: true)
        #expect(typed == [.all, .pinned, .collection(trip), .divider, .ask] + LibraryScope.filteredKinds
            .map(LibraryChip.kind) + [.divider, .date(.today), .date(.week), .otherDevices])
        let applied = LibraryChip.row(collectionIDs: [trip], isSearching: true, offersAsk: true, hasAsk: true)
        #expect(applied.contains(.asked) && !applied.contains(.ask))
        #expect(!LibraryChip.row(collectionIDs: [trip], isSearching: false, offersAsk: true).contains(.ask))
    }

    @Test(
        "an answer sets the kinds and the range, a kind or date chip takes over its half, and ending the search clears it"
    )
    func whenAnAnswerIsApplied_thenChipsAndEndTakeOver() {
        var filter = LibraryFilter(scope: .pinned, kind: .code, date: .week)
        filter.apply(AskPestoQuery(keywords: "invoice", types: [.url, .image], range: .yesterday))
        #expect(filter.kind == nil && filter.date == nil)
        #expect(filter.kinds == [.url, .image])
        #expect(filter.hasAsk && filter.isSelected(.asked))
        #expect(filter.askedSummary == "Links, Images \u{00B7} yesterday")
        #expect(filter.scope == .pinned)

        filter.choose(.kind(.text))
        #expect(filter.kinds == [.text] && filter.askedKinds.isEmpty)
        #expect(filter.askedRange == .yesterday)
        filter.choose(.date(.today))
        #expect(filter.askedRange == .all && !filter.hasAsk)

        filter.apply(AskPestoQuery(keywords: "", types: [.color], range: .month))
        filter.choose(.asked)
        #expect(!filter.hasAsk)
        filter.apply(AskPestoQuery(keywords: "", types: [.color], range: .month))
        filter.endSearch()
        #expect(!filter.hasAsk && filter.kinds.isEmpty)
    }

    @Test("Yesterday is a day with an end, Last 30 Days only a start")
    func whenTheRangeIsAsked_thenTheWindowHasTheMacsBounds() throws {
        let noon = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))
        var filter = LibraryFilter()
        filter.apply(AskPestoQuery(keywords: "", types: [], range: .yesterday))
        let yesterday = filter.dateWindow(now: noon)
        #expect(yesterday.before == Calendar.current.startOfDay(for: noon))
        #expect(yesterday.cutoff == Calendar.current.date(byAdding: .day, value: -1, to: yesterday.before ?? noon))
        filter.apply(AskPestoQuery(keywords: "", types: [], range: .month))
        #expect(filter.dateWindow(now: noon).before == nil)
        #expect(filter.dateWindow(now: noon).cutoff == noon.addingTimeInterval(-30 * 86_400))
    }

    @MainActor
    @Test("the library lists only the asked kinds, within the asked days")
    func whenAskIsApplied_thenTheIndexIsNarrowed() async throws {
        let library = try await MobileTestLibrary()
        try await library.add("a plain note about links")
        try await library.service.ingest(#require(ClipCapture.text("https://copypesto.net/guide")))
        let link = try await library.settle()
        try await library.refreshed()
        let index = try #require(library.store.searchIndex())

        var filter = LibraryFilter()
        filter.apply(AskPestoQuery(keywords: "", types: [.url], range: .today))
        let window = filter.dateWindow()
        let ids = LibraryScope.all.ids(
            in: index, query: "", kinds: filter.kinds, dateCutoff: window.cutoff, dateBefore: window.before
        )
        #expect(ids == [link.id])

        filter.apply(AskPestoQuery(keywords: "", types: [.url], range: .yesterday))
        let before = filter.dateWindow()
        #expect(LibraryScope.all.ids(
            in: index, query: "", kinds: filter.kinds, dateCutoff: before.cutoff, dateBefore: before.before
        ).isEmpty)
    }

    @MainActor
    @Test("with the model off Ask still understands kinds and days, by rule")
    func whenTheModelIsOff_thenTheRulesAnswer() async throws {
        let library = try await MobileTestLibrary()
        library.state.aiAvailability = { .unavailable(.turnedOff) }

        let query = await library.state.askPesto("links about basil from today")

        #expect(query.types == [.url])
        #expect(query.range == .today)
        #expect(query.keywords == "about basil" || query.keywords == "basil")
    }

    @MainActor
    @Test("applying an answer puts its words in the search field and opens the search")
    func whenAnswerIsApplied_thenTheFieldHoldsTheWords() {
        let model = LibraryModel()
        model.apply(AskPestoQuery(keywords: "basil", types: [.url], range: .week))
        #expect(model.query == "basil")
        #expect(model.isSearching)
        #expect(model.filter.kinds == [.url])
    }
}
