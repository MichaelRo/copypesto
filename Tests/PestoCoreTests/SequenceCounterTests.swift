// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("SequenceCounter")
struct SequenceCounterTests {
    @Test("starts at 0")
    func initialPeekIsZero() async {
        let defaults = ThrowawayDefaults.make()
        let counter = SequenceCounter(defaults: defaults, key: "seq")
        #expect(await counter.peekCurrent == 0)
    }

    @Test("next() returns 1, 2, 3 in order")
    func whenMultipleNext_thenMonotonic() async {
        let defaults = ThrowawayDefaults.make()
        let counter = SequenceCounter(defaults: defaults, key: "seq")
        let a = await counter.next()
        let b = await counter.next()
        let c = await counter.next()
        #expect(a == 1)
        #expect(b == 2)
        #expect(c == 3)
    }

    @Test("counter persists across instantiations sharing the same defaults+key")
    func whenPersisted_thenLoadedOnNewInstance() async {
        let suiteName = "test-\(UUID().uuidString)"
        let key = "seq"

        let first = SequenceCounter(defaults: ThrowawayDefaults.make(suiteName), key: key)
        _ = await first.next()
        _ = await first.next()

        let second = SequenceCounter(defaults: ThrowawayDefaults.make(suiteName), key: key)
        let resumed = await second.next()
        #expect(resumed == 3)
    }
}
