// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("DoubleCopyPolicy")
struct DoubleCopyPolicyTests {
    @Test("the keystroke monitor runs only when the user turned the feature on")
    func whenDisabled_thenNoMonitor() {
        #expect(!DoubleCopyPolicy.shouldObserveKeystrokes(enabled: false, systemIntegrations: true))
        #expect(DoubleCopyPolicy.shouldObserveKeystrokes(enabled: true, systemIntegrations: true))
    }

    @Test("never under test, even when enabled")
    func whenUnderTest_thenNoMonitor() {
        #expect(!DoubleCopyPolicy.shouldObserveKeystrokes(enabled: true, systemIntegrations: false))
    }

    @Test("a monitor made before Accessibility was granted is replaced once it is granted")
    func whenAccessibilityArrivesLater_thenReinstall() {
        #expect(DoubleCopyPolicy.needsReinstall(installedWhileTrusted: false, trustedNow: true))
        #expect(!DoubleCopyPolicy.needsReinstall(installedWhileTrusted: true, trustedNow: true))
        #expect(!DoubleCopyPolicy.needsReinstall(installedWhileTrusted: false, trustedNow: false))
    }
}
