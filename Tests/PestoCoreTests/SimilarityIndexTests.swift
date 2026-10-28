// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Similar clips")
struct SimilarityIndexTests {
    private func signature(_ text: String) -> TextSignature {
        TextSignature.make(from: text) ?? TextSignature(values: [UInt32](repeating: 0, count: TextSignature.width))
    }

    @Test("a text too short to compare has no signature")
    func whenTooShort_thenNil() {
        #expect(TextSignature.make(from: "hello there") == nil)
    }

    @Test("the same message with another name and number is close; unrelated text is not")
    func whenTemplateVariants_thenSimilar() {
        let a =
            signature("Hi Anna, your order 48213 has shipped and should arrive on Friday. Thanks for shopping with us!")
        let b =
            signature("Hi Bruno, your order 77 has shipped and should arrive on Friday. Thanks for shopping with us!")
        let c =
            signature(
                "The quarterly report shows revenue growth across all regions with a notable uptick in the south."
            )

        #expect(a.similarity(to: b) > 0.5)
        #expect(a.similarity(to: c) < 0.2)
    }

    @Test("digits and case do not set two copies apart")
    func whenOnlyDigitsAndCaseDiffer_thenIdentical() {
        let a = signature("Invoice 1001 is due on 2026-11-03, please pay promptly to avoid fees")
        let b = signature("INVOICE 2 is due on 99-1-1, please pay promptly to avoid fees")

        #expect(a == b)
    }

    @Test("the index finds look-alikes, forgets removed clips and never returns the clip itself")
    func whenIndexed_thenMatchesFound() {
        var index = SimilarityIndex()
        let ids = (0..<5).map { _ in UUID() }
        for (offset, id) in ids.enumerated() {
            index.insert(
                signature(
                    "Hi person\(offset), your order has shipped and should arrive on Friday. Thanks for shopping!"
                ),
                for: id
            )
        }
        let other = UUID()
        index.insert(
            signature("Completely different text about weather forecasts and rainfall in the northern hills today"),
            for: other
        )

        let found = index
            .matches(
                for: signature("Hi someone, your order has shipped and should arrive on Friday. Thanks for shopping!")
            )
        #expect(Set(found.map(\.id)) == Set(ids))

        index.remove(ids[0])
        let after = index.matches(
            for: signature("Hi person1, your order has shipped and should arrive on Friday. Thanks for shopping!"),
            excluding: ids[1]
        )
        #expect(Set(after.map(\.id)) == Set(ids.dropFirst(2)))
        #expect(index.count == 5)
    }
}
