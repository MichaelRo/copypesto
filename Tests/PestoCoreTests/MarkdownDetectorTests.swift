// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Markdown text is tagged so it can be found")
struct MarkdownDetectorTests {
    @Test("a heading with a list is Markdown, and stays text")
    func whenHeadingAndList_thenTaggedMarkdownAndStillText() {
        let result = ContentClassifier.classify(text: "# Plan\n\n- first thing\n- second thing\n")
        #expect(result.type == .text)
        #expect(result.detectedLanguage == "markdown")
    }

    @Test("a link and bold text together are Markdown")
    func whenLinkAndBold_thenMarkdown() {
        #expect(MarkdownDetector.isMarkdown("Read the **docs** at [Pesto](https://copypesto.net) today"))
    }

    @Test("one stray marker is not a document", arguments: [
        "# not a heading in a sentence?", "just *emphasis* here", "call me at 5 - maybe", "a `lone` code word"
    ])
    func whenOneSignal_thenNot(text: String) {
        #expect(!MarkdownDetector.isMarkdown(text))
    }

    @Test("plain prose is not tagged")
    func whenProse_thenUntagged() {
        let result = ContentClassifier.classify(text: "Dinner is at eight, bring the wine and the good bread.")
        #expect(result.detectedLanguage == nil)
    }

    @Test("text that only looks like the start of Markdown markup is read in bounded time")
    func whenAdversarial_thenFast() {
        let samples = [
            String(repeating: "[", count: 50_000), String(repeating: "**a", count: 16_000),
            String(repeating: "`", count: 50_000), String(repeating: "- a\n", count: 12_000),
            String(repeating: "| a ", count: 12_000)
        ]
        let start = ContinuousClock.now
        for sample in samples {
            _ = MarkdownDetector.isMarkdown(sample)
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }
}
