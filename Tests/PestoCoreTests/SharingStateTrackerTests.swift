// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("SharingStateTracker")
struct SharingStateTrackerTests {
    @Test("the first reading of not-sharing is not a change")
    func whenFirstReadingNotSharing_thenNoChange() {
        var tracker = SharingStateTracker()

        #expect(tracker.update(false) == nil)
    }

    @Test("the first reading of sharing is a change")
    func whenFirstReadingSharing_thenChange() {
        var tracker = SharingStateTracker()

        #expect(tracker.update(true) == true)
    }

    @Test("repeated identical readings emit nothing")
    func whenSameReadingRepeats_thenNoChange() {
        var tracker = SharingStateTracker()
        _ = tracker.update(true)

        #expect(tracker.update(true) == nil)
        #expect(tracker.update(true) == nil)
    }

    @Test("a flip emits the new state once")
    func whenReadingFlips_thenEmitsOnce() {
        var tracker = SharingStateTracker()
        _ = tracker.update(true)

        #expect(tracker.update(false) == false)
        #expect(tracker.update(false) == nil)
    }
}
