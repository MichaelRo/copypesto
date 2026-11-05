// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("NoResultsAdvice")
struct NoResultsAdviceTests {
    @Test("with no filter on it keeps the 500-character note and offers Clear Search")
    func whenNoFilter_thenClearSearch() {
        let advice = NoResultsAdvice.make(query: "invoice")
        #expect(advice.sentence == "Nothing matches “invoice”. Search reads the first 500 characters of each clip.")
        #expect(advice.action == .clearSearch)
        #expect(advice.buttonTitle == "Clear Search")
    }

    @Test("a kind and a date are named, and the button clears the filters")
    func whenKindAndDate_thenNamedAndClearFilters() {
        let advice = NoResultsAdvice.make(query: "invoice", kinds: [.image], date: .today)
        #expect(advice.sentence == "Nothing matches “invoice” with Image and Today on.")
        #expect(advice.action == .clearFilters)
        #expect(advice.buttonTitle == "Clear Filters")
    }

    @Test("three or more are listed with commas and an and")
    func whenThreeFilters_thenListed() {
        let advice = NoResultsAdvice.make(
            query: "x", kinds: [.image, .text], date: .all, appNames: [], sensitiveOnly: true
        )
        #expect(advice.sentence == "Nothing matches “x” with Text, Image and Sensitive on.")
    }

    @Test("kinds come in the bar's order, then date, apps, then the switches")
    func whenAllFilters_thenOrdered() {
        let advice = NoResultsAdvice.make(
            query: "x", kinds: [.code, .text], date: .yesterday, appNames: ["Notes"],
            sensitiveOnly: true, remoteOnly: true, showsHidden: true
        )
        #expect(
            advice.sentence
                == "Nothing matches “x” with Text, Code, Yesterday, Notes, Sensitive, Other Devices and Hidden on."
        )
    }

    @Test("a single filter reads with on")
    func whenOneFilter_thenSingular() {
        let advice = NoResultsAdvice.make(query: "x", showsHidden: true)
        #expect(advice.sentence == "Nothing matches “x” with Hidden on.")
        #expect(advice.action == .clearFilters)
    }

    @Test("Any time is not a filter")
    func whenDateAll_thenNoFilter() {
        #expect(NoResultsAdvice.make(query: "x", date: .all).action == .clearSearch)
    }
}
