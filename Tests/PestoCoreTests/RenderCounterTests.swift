// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Render counter")
struct RenderCounterTests {
    @Test("hits are counted per name and drained once")
    func whenHit_thenDrainReturnsCountsAndResets() {
        let counter = RenderCounter()
        counter.hit("GridView")
        counter.hit("ClipboardCard")
        counter.hit("ClipboardCard")
        #expect(counter.drain() == ["GridView": 1, "ClipboardCard": 2])
        #expect(counter.drain().isEmpty)
    }

    @Test("an amount is added to a name, not counted as one hit")
    func whenAnAmountIsAdded_thenItSums() {
        let counter = RenderCounter()
        counter.add("CardBodyUs", 1200)
        counter.add("CardBodyUs", 300)
        #expect(counter.drain() == ["CardBodyUs": 1500])
    }

    @Test("timing a body outside a perf-timeline run returns its value and records nothing")
    func whenNotRecording_thenTimedReturnsTheValueAndCountsNothing() {
        #expect(RenderProbe.timed("CardBodyUs") { 7 } == 7)
        #expect(RenderProbe.shared.drain().isEmpty)
    }

    @Test("the summary is sorted, so two runs print the same line")
    func whenSummarised_thenNamesAreSorted() {
        #expect(RenderCounter.summary(["b": 2, "a": 1]) == "a=1 b=2")
    }

    @Test("outside a perf-timeline run the shared probe counts nothing")
    func whenNotRecording_thenHitDoesNotCount() {
        RenderProbe.hit("GridView")
        #expect(RenderProbe.shared.drain().isEmpty)
    }
}
