// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("When clip contents are covered for a screen share")
struct ContentCoverTests {
    @Test("a share the detector sees covers the cards only when the setting is on")
    func whenShareDetected_thenCoveredOnlyWithTheSetting() {
        #expect(ContentCover.isCovered(manual: false, settingOn: true, shareDetected: true))
        #expect(!ContentCover.isCovered(manual: false, settingOn: false, shareDetected: true))
    }

    @Test("Hide Contents Now covers the cards whatever the setting and the detector say")
    func whenHiddenByHand_thenCovered() {
        #expect(ContentCover.isCovered(manual: true, settingOn: false, shareDetected: false))
        #expect(ContentCover.isCovered(manual: true, settingOn: true, shareDetected: true))
    }

    @Test("nothing is covered with no share, no setting hit and no hand")
    func whenNothingApplies_thenUncovered() {
        #expect(!ContentCover.isCovered(manual: false, settingOn: true, shareDetected: false))
        #expect(!ContentCover.isCovered(manual: false, settingOn: false, shareDetected: false))
    }
}
