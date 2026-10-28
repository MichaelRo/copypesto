// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Inferring a template from look-alike clips")
struct TemplateInferrerTests {
    @Test("words that differ become fields, and the rest stays as written")
    func whenClipsDifferInNameAndNumber_thenTwoFields() throws {
        let proposal = try #require(TemplateInferrer.propose(from: [
            "Hi Anna, your order 4821 has shipped and will arrive on Friday.",
            "Hi Bruno, your order 77 has shipped and will arrive on Friday.",
            "Hi Chloe, your order 9034 has shipped and will arrive on Friday."
        ]))

        #expect(proposal
            .template == "Hi {{input:Name}}, your order {{input:Number}} has shipped and will arrive on Friday.")
        #expect(proposal.fields.map(\.label) == ["Name", "Number"])
    }

    @Test("line breaks and spacing are kept")
    func whenMultiline_thenLayoutKept() throws {
        let proposal = try #require(TemplateInferrer.propose(from: [
            "Dear Ana,\n\nThanks for your note about the invoice.\nBest, Mo",
            "Dear Bo,\n\nThanks for your note about the invoice.\nBest, Mo",
            "Dear Cy,\n\nThanks for your note about the invoice.\nBest, Mo"
        ]))

        #expect(proposal.template == "Dear {{input:Name}},\n\nThanks for your note about the invoice.\nBest, Mo")
    }

    @Test("clips that are the same, or share too little, are not a template")
    func whenIdenticalOrUnrelated_thenNoProposal() {
        let same = Array(repeating: "Hello there, this is the very same message again today.", count: 3)
        let unrelated = [
            "Alpha beta gamma delta epsilon zeta eta theta iota kappa",
            "One two three four five six seven eight nine ten eleven",
            "Red green blue yellow orange purple black white brown grey"
        ]

        #expect(TemplateInferrer.propose(from: same) == nil)
        #expect(TemplateInferrer.propose(from: unrelated) == nil)
    }

    @Test("a repeated label gets a number so every field is asked separately")
    func whenTwoNameSlots_thenLabelsDiffer() throws {
        let proposal = try #require(TemplateInferrer.propose(from: [
            "From Ana to Bob: the report is ready for review this week.",
            "From Cy to Dee: the report is ready for review this week.",
            "From Eve to Flo: the report is ready for review this week."
        ]))

        #expect(proposal.fields.map(\.label) == ["Name", "Name 2"])
    }

    @Test("a date in a clip is offered as a date placeholder")
    func whenLiteralDate_thenDatePlaceholder() {
        #expect(TemplateInferrer
            .replacingDates(in: "Invoice due 2026-11-03 for Acme") == "Invoice due {{isodate}} for Acme")
        #expect(TemplateInferrer.replacingDates(in: "no dates here") == nil)
    }
}
