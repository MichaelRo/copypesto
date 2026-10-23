// SPDX-License-Identifier: MIT
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
}
