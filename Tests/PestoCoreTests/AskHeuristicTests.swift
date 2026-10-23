// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("AskHeuristic")
struct AskHeuristicTests {
    @Test("one word, or two plain words, is a search for those words")
    func whenShort_thenNotAQuestion() {
        #expect(!AskHeuristic.looksLikeQuestion(""))
        #expect(!AskHeuristic.looksLikeQuestion("Quarterly"))
        #expect(!AskHeuristic.looksLikeQuestion("meeting notes"))
    }

    @Test("a question mark makes it a question, whatever its length")
    func whenQuestionMark_thenQuestion() {
        #expect(AskHeuristic.looksLikeQuestion("invoice?"))
    }

    @Test("a question or command word, or a time or type word, with another word makes it a question")
    func whenIntentWord_thenQuestion() {
        #expect(AskHeuristic.looksLikeQuestion("find invoice"))
        #expect(AskHeuristic.looksLikeQuestion("images today"))
        #expect(AskHeuristic.looksLikeQuestion("slack links"))
        #expect(AskHeuristic.looksLikeQuestion("yesterday meeting"))
    }

    @Test("three words or more read as a sentence")
    func whenThreeWords_thenQuestion() {
        #expect(AskHeuristic.looksLikeQuestion("images from today"))
        #expect(AskHeuristic.looksLikeQuestion("quarterly report draft"))
    }

    @Test("a sentence that has no results is asked when Return finds nothing")
    func whenNoResults_thenReturnAsks() {
        #expect(AskHeuristic.returnAsks(text: "links from slack last week", resultCount: 0))
        #expect(!AskHeuristic.returnAsks(text: "links from slack last week", resultCount: 4))
        #expect(!AskHeuristic.returnAsks(text: "xyz", resultCount: 0))
    }
}
