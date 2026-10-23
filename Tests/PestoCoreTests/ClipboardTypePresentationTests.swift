// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ClipboardType presentation")
struct ClipboardTypePresentationTests {
    @Test("every type has a label and a symbol")
    func everyTypeHasBoth() {
        for type in ClipboardType.allCases {
            #expect(!type.presentation.label.isEmpty)
            #expect(!type.presentation.symbolName.isEmpty)
        }
    }

    @Test("symbols and labels are unique, so the badge and the filter chip can be told apart")
    func valuesAreUnique() {
        let presentations = ClipboardType.allCases.map(\.presentation)

        #expect(Set(presentations.map(\.label)).count == presentations.count)
        #expect(Set(presentations.map(\.symbolName)).count == presentations.count)
    }

    @Test("URLs are called Link everywhere")
    func urlIsLink() {
        #expect(ClipboardType.url.presentation.label == "Link")
    }
}
