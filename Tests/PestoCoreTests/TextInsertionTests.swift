// SPDX-License-Identifier: MIT
import ApplicationServices
import Foundation
import Testing
@testable import PestoCore

private final class FakeTarget: AXTextTarget, @unchecked Sendable {
    var range: CFRange? = CFRange(location: 5, length: 0)
    var count: Int? = 20
    var acceptsWrite = true
    var writeTakesEffect = true
    var caretMovesOnWrite = true
    private(set) var setTexts: [String] = []
    private(set) var caretSets: [CFRange] = []

    func selectedRange() -> CFRange? {
        range
    }

    func characterCount() -> Int? {
        count
    }

    func setSelectedText(_ text: String) -> Bool {
        setTexts.append(text)
        guard acceptsWrite else { return false }
        if writeTakesEffect, let current = range {
            count = count.map { $0 - current.length + (text as NSString).length }
            if caretMovesOnWrite { range = CFRange(location: current.location + (text as NSString).length, length: 0) }
        }
        return true
    }

    func setSelectedRange(_ newRange: CFRange) {
        caretSets.append(newRange)
        range = newRange
    }
}

@Suite("TextInsertion")
struct TextInsertionTests {
    @Test("a write that changes the character count succeeds and moves the caret after the text")
    func whenWriteTakesEffect_thenSucceedsAndCaretAfterText() {
        let target = FakeTarget()

        let inserted = TextInsertion.insert("hello", into: target)

        #expect(inserted)
        #expect(target.caretSets.last?.location == 10)
    }

    @Test("AX reporting success while the field is unchanged falls through to Tier 2")
    func whenSetSucceedsButCountUnchanged_thenFallsThrough() {
        let target = FakeTarget()
        target.writeTakesEffect = false

        #expect(TextInsertion.insert("hello", into: target) == false)
        #expect(target.caretSets.isEmpty)
    }

    @Test("without a character count, an unchanged selection range means the write did not land")
    func whenNoCountAndRangeUnchanged_thenFallsThrough() {
        let target = FakeTarget()
        target.count = nil
        target.writeTakesEffect = false

        #expect(TextInsertion.insert("hello", into: target) == false)
    }

    @Test("without a character count, a moved range counts as success")
    func whenNoCountAndRangeMoved_thenSucceeds() {
        let target = FakeTarget()
        target.count = nil

        #expect(TextInsertion.insert("hello", into: target))
    }

    @Test("a rejected write fails")
    func whenSetRejected_thenFails() {
        let target = FakeTarget()
        target.acceptsWrite = false

        #expect(TextInsertion.insert("hello", into: target) == false)
    }

    @Test("no selection range means Tier 1 is not possible")
    func whenNoSelectionRange_thenFailsWithoutWriting() {
        let target = FakeTarget()
        target.range = nil

        #expect(TextInsertion.insert("hello", into: target) == false)
        #expect(target.setTexts.isEmpty)
    }

    @Test("emoji are counted in UTF-16 units")
    func whenTextHasEmoji_thenCaretUsesUTF16Length() {
        let target = FakeTarget()

        #expect(TextInsertion.insert("a😀", into: target))
        #expect(target.caretSets.last?.location == 5 + 3)
    }

    @Test("replacing a selection with text of the same length is judged by the selection, not the unchanged count")
    func whenTheReplacementHasTheSameLength_thenTheSelectionDecides() {
        let ignored = FakeTarget()
        ignored.range = CFRange(location: 2, length: 3)
        ignored.writeTakesEffect = false
        #expect(!TextInsertion.insert("abc", into: ignored), "the app ignored the write: Tier 2 must run")

        let landed = FakeTarget()
        landed.range = CFRange(location: 2, length: 3)
        #expect(TextInsertion.insert("abc", into: landed), "the write landed and the caret moved past it")
    }

    @Test("when caret offset is provided, caret is positioned before the end")
    func whenCaretOffsetProvided_thenCaretIsPositionedBeforeTheEnd() {
        let target = FakeTarget()

        let inserted = TextInsertion.insert("hello world", into: target, caretOffsetFromEnd: 6)

        #expect(inserted)
        // range location was 5. "hello " has length 5. target location = 5 + 5 = 10
        #expect(target.caretSets.last?.location == 10)
    }

    @Test("when caret offset exceeds length, caret is clamped to start")
    func whenCaretOffsetExceedsLength_thenCaretIsClampedToStart() {
        let target = FakeTarget()

        let inserted = TextInsertion.insert("hello", into: target, caretOffsetFromEnd: 100)

        #expect(inserted)
        #expect(target.caretSets.last?.location == 5)
    }

    @Test("when text has emoji and caret offset is provided, UTF-16 offset is calculated correctly")
    func whenTextHasEmoji_andCaretOffsetProvided_thenCaretUsesUTF16Prefix() {
        let target = FakeTarget()

        // "hi 👋 world" -> prefix before 6 characters from end (" world") is "hi 👋"
        // "hi " is 3 UTF-16, "👋" is 2 UTF-16. Total prefix = 5.
        // range.location is 5. target location = 5 + 5 = 10.
        let inserted = TextInsertion.insert("hi 👋 world", into: target, caretOffsetFromEnd: 6)

        #expect(inserted)
        #expect(target.caretSets.last?.location == 10)
    }
}
