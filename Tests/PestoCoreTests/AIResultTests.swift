// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("AIResult")
struct AIResultTests {
    @Test("an answer is not protected unless it was asked about a secret")
    func whenNothingSaysOtherwise_thenNotProtected() {
        #expect(!AIResult(action: .summarize, sourcePreview: "x", result: "y").isProtected)
        #expect(AIResult(action: .summarize, sourcePreview: "x", result: "y", isProtected: true).isProtected)
    }

    @Test("marking an answer protected keeps everything else about it")
    func whenMarkedProtected_thenTheRestIsKept() {
        let answer = AIResult(action: .toneConcise, sourcePreview: "src", result: "out")

        let marked = answer.protecting(true)

        #expect(marked.isProtected)
        #expect(marked.id == answer.id)
        #expect(marked.result == "out")
        #expect(marked.sourcePreview == "src")
    }

    @Test("only a finished answer can be pasted, never an error message")
    func whenError_thenNotPastable() {
        #expect(AIResult(action: .summarize, sourcePreview: "x", result: "y").canPaste)
        #expect(!AIResult(action: .summarize, sourcePreview: "x", result: "No", isError: true).canPaste)
        #expect(!AIResult(action: .summarize, sourcePreview: "x", result: "  \n").canPaste)
    }

    @Test("an answer remembers the clip it was made from, and keeps everything else")
    func whenMadeFrom_thenSourceKept() {
        let clip = UUID()
        let answer = AIResult(action: .summarize, sourcePreview: "src", result: "out", isProtected: true)

        let marked = answer.madeFrom(clip)

        #expect(marked.sourceItemID == clip)
        #expect(marked.isProtected)
        #expect(marked.id == answer.id)
        #expect(answer.sourceItemID == nil)
    }
}
