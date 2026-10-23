// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("AIChunker")
struct AIChunkerTests {
    private func words(_ count: Int) -> String {
        (0..<count).map { "word\($0)" }.joined(separator: " ")
    }

    @Test("text inside the budget is one part and nothing is cut")
    func whenFits_thenOnePart() {
        let result = AIChunker.parts(of: "a short note", budget: 100)
        #expect(result.parts.map(\.text) == ["a short note"])
        #expect(result.parts.first?.start == 1 && result.parts.first?.end == 12)
        #expect(!result.isCut)
    }

    @Test("no part is over the budget and the parts, in order, cover the text")
    func whenLong_thenBoundedAndComplete() {
        let text = words(400)
        let result = AIChunker.parts(of: text, budget: 200)
        #expect(result.parts.count > 1)
        #expect(result.parts.allSatisfy { $0.end - $0.start + 1 <= 200 })
        #expect(result.parts.first?.start == 1)
        #expect(result.parts.last?.end == text.count)
        for (a, b) in zip(result.parts, result.parts.dropFirst()) {
            #expect(b.start == a.end + 1)
        }
        #expect(result.parts.map(\.text).joined(separator: " ") == text)
    }

    @Test("a blank line is the preferred cut, then the end of a sentence, then a line end, then whitespace")
    func whenBoundaries_thenPreferenceOrder() {
        let blank = String(repeating: "a ", count: 30) + "\n\n" + String(repeating: "b ", count: 30)
        #expect(AIChunker.parts(of: blank, budget: 80).parts.first?.text.hasSuffix("a") == true)
        let sentence = String(repeating: "a ", count: 20) + "end. " + String(repeating: "b ", count: 30)
        #expect(AIChunker.parts(of: sentence, budget: 60).parts.first?.text.hasSuffix("end.") == true)
        let line = String(repeating: "a ", count: 20) + "tail\n" + String(repeating: "b ", count: 30)
        #expect(AIChunker.parts(of: line, budget: 60).parts.first?.text.hasSuffix("tail") == true)
        let spaces = String(repeating: "word ", count: 30)
        #expect(AIChunker.parts(of: spaces, budget: 50).parts.allSatisfy { !$0.text.hasPrefix("ord") })
    }

    @Test("one very long word is cut where the budget ends")
    func whenOneWord_thenHardCut() {
        let result = AIChunker.parts(of: String(repeating: "x", count: 250), budget: 100)
        #expect(result.parts.map { $0.end - $0.start + 1 } == [100, 100, 50])
    }

    @Test("empty and whitespace-only text has no parts")
    func whenEmpty_thenNone() {
        #expect(AIChunker.parts(of: "", budget: 100).parts.isEmpty)
        #expect(AIChunker.parts(of: "  \n\n ", budget: 100).parts.isEmpty)
    }

    @Test("only the first maxCharacters are read, and the result says how much was left")
    func whenOverCeiling_thenCut() {
        let result = AIChunker.parts(of: words(500), budget: 100, maxCharacters: 1000)
        #expect(result.parts.last?.end ?? 0 <= 1000)
        #expect(result.isCut)
        #expect(result.readable == 1000)
        #expect(result.total == words(500).count)
    }

    @Test("emoji and combining marks are never split inside a character")
    func whenUnicode_thenWholeCharacters() {
        let text = String(repeating: "👩‍👩‍👧‍👦 é ", count: 100)
        let result = AIChunker.parts(of: text, budget: 30)
        #expect(result.parts.map(\.text).joined(separator: " ").count <= text.count)
        #expect(result.parts.allSatisfy { !$0.text.isEmpty })
    }

    @Test("a 5 MB text is chunked from its first 100,000 characters in well under a frame")
    func whenHuge_thenFast() {
        let huge = String(repeating: "lorem ipsum dolor sit amet. ", count: 180_000)
        let clock = ContinuousClock()
        var result = AIParts(parts: [], total: 0, readable: 0)
        let elapsed = clock.measure {
            result = AIChunker.parts(of: huge, budget: 8700, totalCharacters: 5_040_000)
        }
        #expect(elapsed < .milliseconds(50))
        #expect(result.readable == AIChunker.maxCharacters && result.isCut)
        #expect(result.parts.count >= 11 && result.parts.count <= 13)
    }
}
