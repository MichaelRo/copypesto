// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("SearchMatching")
struct SearchMatchingTests {
    @Test("matching ignores case")
    func ignoresCase() {
        #expect(SearchMatching.matches("Quarterly Report", query: "quarterly"))
    }

    @Test("matching ignores diacritics")
    func ignoresDiacritics() {
        #expect(SearchMatching.matches("Café au lait", query: "cafe"))
    }

    @Test("a substring anywhere matches, a missing one does not")
    func substringSemantics() {
        #expect(SearchMatching.matches("alpha beta gamma", query: "beta"))
        #expect(!SearchMatching.matches("alpha beta gamma", query: "delta"))
    }

    @Test("an empty query matches everything")
    func emptyQueryMatches() {
        #expect(SearchMatching.matches("anything", query: ""))
    }

    @Test("Hebrew text matches")
    func hebrew() {
        #expect(SearchMatching.matches("שלום עולם", query: "עולם"))
    }
}
