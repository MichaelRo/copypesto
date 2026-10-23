// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Perf timeline")
struct PerfTimelineTests {
    @Test("a normal or hosted launch records no timeline")
    func whenNotBenchLaunch_thenDisabled() {
        let normal = RuntimeConfiguration(mode: .normal, session: "s", seed: .basic, accessibility: .trusted)
        var uiTest = RuntimeConfiguration(mode: .uiTest, session: "s", seed: .basic, accessibility: .trusted)
        #expect(!PerfTimeline.isEnabled(for: normal))
        #expect(!PerfTimeline.isEnabled(for: uiTest))
        uiTest.usesRealPasteboard = true
        #expect(PerfTimeline.isEnabled(for: uiTest))
        uiTest.usesRealPasteboard = false
        uiTest.recordsPerfTimeline = true
        #expect(PerfTimeline.isEnabled(for: uiTest), "the scroll bench records without taking over the clipboard")
        var hosted = RuntimeConfiguration(mode: .hostedTests, session: "s", seed: .basic, accessibility: .trusted)
        hosted.usesRealPasteboard = true
        #expect(!PerfTimeline.isEnabled(for: hosted))
    }

    @Test("a line holds the channel, the stage and the start and end on the system uptime clock")
    func whenFormatted_thenTabSeparated() {
        #expect(PerfTimeline
            .line(channel: "Paste", name: "activate", start: 10, end: 25) == "Paste\tactivate\t10\t25\n")
    }

    @Test("the clock is the uptime clock the bench's other processes read")
    func whenRead_thenUptimeNanoseconds() {
        let before = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let reading = PerfTimeline.now()
        let after = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        #expect(before <= reading && reading <= after)
    }
}
