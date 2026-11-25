// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import XCTest
@testable import Pesto

@MainActor
final class AskApplyTests: XCTestCase {
    func test_whenQueryApplied_thenSearchTextAndFiltersAreSet() {
        let state = AppState()

        state.apply(AskPestoQuery(keywords: "invoice", types: [.url, .file], range: .week))

        XCTAssertEqual(state.searchText, "invoice")
        XCTAssertEqual(state.searchTypeFilter, ["url", "file"])
        XCTAssertEqual(state.searchDateFilter, .week)
        XCTAssertTrue(state.isSearchActive)

        state.apply(AskPestoQuery(keywords: "", types: [.text], range: .yesterday))
        XCTAssertEqual(state.searchText, "")
        XCTAssertEqual(state.searchTypeFilter, ["text"])
        XCTAssertEqual(state.searchDateFilter, .yesterday)
    }

    func test_whenQueryNamesACustomRange_thenTheDateFilterHoldsIt() {
        let state = AppState()
        let range = DateInterval(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 90_000))

        state.apply(AskPestoQuery(keywords: "invoice", types: [], range: .custom(range)))

        XCTAssertEqual(state.searchDateFilter, .custom(range))
        XCTAssertTrue(state.isSearchActive)
    }

    func test_whenQueryHasNoFilters_thenEarlierFiltersAreCleared() {
        let state = AppState()
        state.searchTypeFilter = ["image"]
        state.searchDateFilter = .month

        state.apply(AskPestoQuery(keywords: "x", types: [], range: .all))

        XCTAssertTrue(state.searchTypeFilter.isEmpty)
        XCTAssertEqual(state.searchDateFilter, .all)
    }

    func test_recentSearches_areOfferedOnAnEmptyFieldButNotOverFilters() {
        let state = AppState()

        XCTAssertTrue(state.offersRecentSearches(true, history: ["links"]))
        XCTAssertFalse(state.offersRecentSearches(false, history: ["links"]), "not while the field is unfocused")
        XCTAssertFalse(state.offersRecentSearches(true, history: []), "nothing to offer")

        state.apply(AskPestoQuery(keywords: "", types: [.url], range: .today))

        XCTAssertFalse(state.offersRecentSearches(true, history: ["links"]), "Ask has set filters; leave them visible")
    }

    func test_whenAskCancelledMidFlight_thenStaleQueryIsDropped() async {
        struct DelayedInterpreter: QueryInterpreting {
            let onStart: @Sendable () -> Void
            func interpret(_: String) async throws -> AskPestoQuery {
                onStart()
                try? await Task.sleep(for: .milliseconds(50))
                return AskPestoQuery(keywords: "stale", types: [.url], range: .week)
            }
        }

        let state = AppState()
        state.searchText = "links from last week"
        state.isSearchActive = true
        let task = Task {
            await state.askPesto(using: FallbackQueryInterpreter(primary: DelayedInterpreter {
                Task { @MainActor in
                    state.cancelAsk()
                    state.searchText = "fresh"
                }
            }))
        }
        await task.value

        XCTAssertEqual(state.searchText, "fresh")
        XCTAssertTrue(state.searchTypeFilter.isEmpty)
        XCTAssertEqual(state.searchDateFilter, .all)
    }
}
