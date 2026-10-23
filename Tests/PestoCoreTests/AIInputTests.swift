// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("AIInput")
struct AIInputTests {
    @Test("text inside the budget goes whole and says so")
    func whenInsideBudget_thenWhole() {
        let input = AIInput.make("a short note", budget: 100)

        #expect(input.text == "a short note")
        #expect(input.coverage == AIResult.Coverage(shown: 12, total: 12))
        #expect(!input.coverage.isPartial)
    }

    @Test("text over the budget is cut at a word, never inside one, and says how much was kept")
    func whenOverBudget_thenCutAtAWord() {
        let input = AIInput.make("alpha beta gamma delta", budget: 13)

        #expect(input.text == "alpha beta")
        #expect(input.coverage == AIResult.Coverage(shown: 10, total: 22))
        #expect(input.coverage.isPartial)
    }

    @Test("a line break is a cut point too, and a single word longer than the budget is cut where the budget ends")
    func whenNoSpaces_thenCutAtTheBudget() {
        #expect(AIInput.make("one two\nthree four", budget: 12).text == "one two")
        #expect(AIInput.make(String(repeating: "x", count: 50), budget: 20).text.count == 20)
    }

    @Test("text that is already only a preview of a longer clip counts as partial")
    func whenGivenTotalLarger_thenPartial() {
        let input = AIInput.make("the first 500 characters", budget: 8000, totalCharacters: 90_000)

        #expect(input.text == "the first 500 characters")
        #expect(input.coverage == AIResult.Coverage(shown: 24, total: 90_000))
    }

    @Test("the budget follows the model's context, with a floor and a ceiling, and 8,000 when the size is unknown")
    func budgetFromContext() {
        #expect(AIInputBudget.characters(contextTokens: nil) == 8000)
        #expect(AIInputBudget.characters(contextTokens: 4096) == 8688)
        #expect(AIInputBudget.characters(contextTokens: 1000) == 4000)
        #expect(AIInputBudget.characters(contextTokens: 1_000_000) == 40_000)
    }
}
