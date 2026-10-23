// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("PasteStack")
struct PasteStackTests {
    private func makeItem(_ text: String) -> PasteStack.Item {
        PasteStack.Item(previewText: text, payloadKind: .text(text))
    }

    @Test
    func whenCreated_currentIndexIsZero() {
        let stack = PasteStack(items: [makeItem("a"), makeItem("b")])
        #expect(stack.currentIndex == 0)
    }

    @Test
    func whenCreated_currentIsFirstItem() {
        let stack = PasteStack(items: [makeItem("hello"), makeItem("world")])
        #expect(stack.current?.previewText == "hello")
    }

    @Test
    func whenAdvanced_indexIncrements() {
        var stack = PasteStack(items: [makeItem("a"), makeItem("b"), makeItem("c")])
        stack.advance()
        #expect(stack.currentIndex == 1)
        #expect(stack.current?.previewText == "b")
    }

    @Test
    func whenAdvancedToEnd_isComplete() {
        var stack = PasteStack(items: [makeItem("a"), makeItem("b")])
        stack.advance()
        stack.advance()
        #expect(stack.isComplete)
        #expect(stack.current == nil)
    }

    @Test
    func whenAdvancedPastEnd_isNoOp() {
        var stack = PasteStack(items: [makeItem("only")])
        stack.advance()
        stack.advance() // no-op
        #expect(stack.isComplete)
        #expect(stack.currentIndex == 1)
    }

    @Test
    func progressLabel_formatsAsNofM() {
        var stack = PasteStack(items: [makeItem("a"), makeItem("b"), makeItem("c")])
        #expect(stack.progressLabel == "1/3")
        stack.advance()
        #expect(stack.progressLabel == "2/3")
        stack.advance()
        #expect(stack.progressLabel == "3/3")
    }

    @Test
    func count_returnsItemCount() {
        let stack = PasteStack(items: [makeItem("x"), makeItem("y")])
        #expect(stack.count == 2)
    }

    @Test
    func singleItem_completesAfterOneAdvance() {
        var stack = PasteStack(items: [makeItem("sole")])
        #expect(!stack.isComplete)
        stack.advance()
        #expect(stack.isComplete)
    }

    @Test
    func nonTextItem_payloadKindIsNonText() {
        let item = PasteStack.Item(previewText: "[image]", payloadKind: .nonText)
        #expect(item.payloadKind == .nonText)
    }

    @Test
    func itemWithBlobData_storesDataAndType() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let item = PasteStack.Item(
            previewText: "img",
            payloadKind: .nonText,
            pasteboardData: data,
            pasteboardType: "public.png"
        )
        #expect(item.pasteboardData == data)
        #expect(item.pasteboardType == "public.png")
    }

    @Test("a selection over the limit is cut to the limit, and the rest is counted")
    func whenSelectionIsOverTheLimit_thenItIsCut() {
        let selection = Array(0..<(PasteStack.maxItems + 25))

        let result = PasteStack.limited(selection)

        #expect(result.kept == Array(0..<PasteStack.maxItems))
        #expect(result.leftOut == 25)
    }

    @Test("a selection within the limit is kept whole")
    func whenSelectionIsWithinTheLimit_thenNothingIsLeftOut() {
        let result = PasteStack.limited(Array(0..<5))

        #expect(result.kept.count == 5)
        #expect(result.leftOut == 0)
    }
}
