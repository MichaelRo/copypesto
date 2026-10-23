// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("CollectionSymbol")
struct CollectionSymbolTests {
    @Test("an emoji is recognised")
    func whenEmoji_thenIsEmoji() {
        #expect(CollectionSymbol.isEmoji("🌿"))
        #expect(CollectionSymbol.isEmoji("📌"))
    }

    @Test("an SF Symbol name is not an emoji")
    func whenSymbolName_thenNotEmoji() {
        #expect(!CollectionSymbol.isEmoji("tray.2"))
        #expect(!CollectionSymbol.isEmoji("star.fill"))
    }

    @Test("digits and plain characters that are technically emoji-capable are not treated as emoji")
    func whenDigitOrHash_thenNotEmoji() {
        #expect(!CollectionSymbol.isEmoji("1"))
        #expect(!CollectionSymbol.isEmoji("#"))
    }

    @Test("an empty name is not an emoji")
    func whenEmpty_thenNotEmoji() {
        #expect(!CollectionSymbol.isEmoji(""))
    }
}
