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
