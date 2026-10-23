// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Search history")
struct SearchHistoryTests {
    @Test("nothing stored means no entries")
    func whenEmpty_thenNoEntries() {
        #expect(SearchHistory.entries(from: "").isEmpty)
    }

    @Test("a new search goes to the front")
    func whenRecorded_thenMostRecentFirst() {
        var raw = ""
        for query in ["one", "two", "three"] {
            raw = SearchHistory.recording(query, in: raw)
        }
        #expect(SearchHistory.entries(from: raw) == ["three", "two", "one"])
    }

    @Test("repeating a search moves it to the front instead of duplicating it")
    func whenRepeated_thenMovedToFront() {
        var raw = ""
        for query in ["one", "two", "one"] {
            raw = SearchHistory.recording(query, in: raw)
        }
        #expect(SearchHistory.entries(from: raw) == ["one", "two"])
    }

    @Test("blank searches are not recorded, and spaces around a search are trimmed")
    func whenBlankOrPadded_thenHandled() {
        #expect(SearchHistory.recording("   ", in: "a") == "a")
        #expect(SearchHistory.recording("", in: "a") == "a")
        #expect(SearchHistory.entries(from: SearchHistory.recording("  padded  ", in: "")) == ["padded"])
    }

    @Test("only the ten most recent searches are kept")
    func whenMoreThanTen_thenOldestDropped() {
        var raw = ""
        for number in 1...12 {
            raw = SearchHistory.recording("q\(number)", in: raw)
        }
        let entries = SearchHistory.entries(from: raw)
        #expect(entries.count == 10)
        #expect(entries.first == "q12" && entries.last == "q3")
    }

    @Test("a search containing the storage separator cannot split into two entries")
    func whenSeparatorInQuery_thenStaysOneEntry() {
        let raw = SearchHistory.recording("a|||b", in: "")
        #expect(SearchHistory.entries(from: raw).count == 1)
    }

    @Test("a query that is itself a secret is not kept in the recent searches")
    func whenTheQueryIsASecret_thenItIsNotRecorded() {
        #expect(SearchHistory.recording("4242 4242 4242 4242", in: "invoice") == "invoice")
        #expect(SearchHistory.recording("sk-ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", in: "").isEmpty)
        #expect(SearchHistory.recording("quarterly report", in: "invoice") == "quarterly report|||invoice")
    }
}
