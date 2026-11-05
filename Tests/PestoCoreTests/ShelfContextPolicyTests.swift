// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("How long the shelf remembers where it was")
struct ShelfContextPolicyTests {
    private let closed = Date(timeIntervalSince1970: 1_000_000)

    @Test("a shelf that was never closed has nothing to forget")
    func whenNeverClosed_thenNoReset() {
        #expect(!ShelfContextPolicy.shouldReset(closedAt: nil, now: closed))
    }

    @Test("reopening within the memory keeps the collection and filters")
    func whenReopenedSoon_thenKept() {
        #expect(!ShelfContextPolicy.shouldReset(closedAt: closed, now: closed.addingTimeInterval(89)))
    }

    @Test("reopening after the memory starts from All again, and the limit itself resets")
    func whenReopenedLate_thenReset() {
        #expect(ShelfContextPolicy.shouldReset(closedAt: closed, now: closed.addingTimeInterval(90)))
        #expect(ShelfContextPolicy.shouldReset(closedAt: closed, now: closed.addingTimeInterval(3600)))
    }

    @Test("a clock that went backwards does not wipe the shelf")
    func whenClockWentBack_thenKept() {
        #expect(!ShelfContextPolicy.shouldReset(closedAt: closed, now: closed.addingTimeInterval(-30)))
    }
}
