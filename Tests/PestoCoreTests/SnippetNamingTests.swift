// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Naming a snippet's fields")
struct SnippetNamingTests {
    private let template = "Hi {{input:Name}}, your order {{input:Number}} has shipped."

    @Test("the model sees the template with numbered blanks and never a field's real values")
    func whenPrompted_thenBlanksAreNumbered() {
        let request = SnippetNaming.request(for: template)

        #expect(request.message.contains("Hi [1], your order [2] has shipped."))
        #expect(!request.message.contains("{{"))
    }

    @Test("names come back one per line, numbered or not, and are applied in order")
    func whenModelAnswers_thenLabelsRenamed() throws {
        let renamed = try #require(SnippetNaming.applying("1. Customer name\n2) Order number", to: template))

        #expect(renamed == "Hi {{input:Customer name}}, your order {{input:Order number}} has shipped.")
    }

    @Test("a wrong number of names, a name with braces or quotes, and a repeat are refused")
    func whenAnswerIsUnusable_thenNil() {
        #expect(SnippetNaming.applying("Only one", to: template) == nil)
        #expect(SnippetNaming.applying("A}}\nB", to: template) == nil)
        #expect(SnippetNaming.applying("Same\nSame", to: template) == nil)
        #expect(SnippetNaming.applying("A\n\(String(repeating: "x", count: 80))", to: template) == nil)
    }

    @Test("the model is asked once, and its failure leaves the template alone")
    func whenModelFails_thenTemplateKept() async {
        let result = await SnippetNaming.suggest(for: template) { _, _ in throw CancellationError() }

        #expect(result == nil)
    }

    @Test("a model that answers is applied")
    func whenModelAnswers_thenSuggested() async {
        let result = await SnippetNaming.suggest(for: template) { _, _ in "Customer\nOrder" }

        #expect(result == "Hi {{input:Customer}}, your order {{input:Order}} has shipped.")
    }
}
