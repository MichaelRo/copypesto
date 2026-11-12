// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Switch quality policy")
struct SwitchQualityPolicyTests {
    private let start = ContinuousClock.now

    private func at(_ millis: Int) -> ContinuousClock.Instant {
        start + .milliseconds(millis)
    }

    @Test("the first switch is drawn in full, whatever came before")
    func whenNothingIsKnown_thenFull() {
        var policy = SwitchQualityPolicy()
        #expect(policy.quality(at: at(0)) == .full)
    }

    @Test("only the third quick switch in a row after a slow one is drawn light")
    func whenSwitchesFollowQuicklyAfterASlowOne_thenTheThirdIsLight() {
        var policy = SwitchQualityPolicy()
        #expect(policy.quality(at: at(0)) == .full)
        policy.committed(.full, millis: 55)
        #expect(policy.quality(at: at(200)) == .full)
        policy.committed(.full, millis: 55)
        #expect(policy.quality(at: at(350)) == .light)
    }

    @Test("a switch after a pause is drawn in full, so a person who switches once always sees real cards")
    func whenTheNextSwitchComesAfterThePause_thenFull() {
        var policy = SwitchQualityPolicy()
        _ = policy.quality(at: at(0))
        policy.committed(.full, millis: 55)
        #expect(policy.quality(at: at(2000)) == .full)
    }

    @Test("a Mac where a full switch is quick never sees a light one")
    func whenFullSwitchesAreFast_thenNeverLight() {
        var policy = SwitchQualityPolicy()
        _ = policy.quality(at: at(0))
        policy.committed(.full, millis: 12)
        #expect(policy.quality(at: at(100)) == .full)
        policy.committed(.full, millis: 12)
        #expect(policy.quality(at: at(200)) == .full)
    }

    @Test("a light switch's own speed does not make the next one look cheap, or it would flip back and forth")
    func whenALightSwitchCommitsQuickly_thenTheEstimateOfAFullOneStays() {
        var policy = SwitchQualityPolicy()
        _ = policy.quality(at: at(0))
        policy.committed(.full, millis: 55)
        #expect(policy.quality(at: at(150)) == .full)
        policy.committed(.full, millis: 55)
        #expect(policy.quality(at: at(300)) == .light)
        policy.committed(.light, millis: 9)
        #expect(policy.quality(at: at(450)) == .light)
    }

    @Test("when a full switch turns out quick, later quick switches stay full")
    func whenAFullSwitchIsLaterFast_thenTheEstimateRecovers() {
        var policy = SwitchQualityPolicy()
        _ = policy.quality(at: at(0))
        policy.committed(.full, millis: 55)
        #expect(policy.quality(at: at(5000)) == .full)
        policy.committed(.full, millis: 20)
        #expect(policy.quality(at: at(5100)) == .full)
    }
}
