// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Link preview policy")
struct LinkPreviewPolicyTests {
    private func suite() -> UserDefaults {
        ThrowawayDefaults.make()
    }

    @Test("previews are off until the user turns them on, because a preview asks the linked site")
    func whenNothingStored_thenOff() {
        #expect(!LinkPreviewPolicy.isEnabled(in: suite(), mode: .normal))
        #expect(Setting.linkPreviews.defaultValue == false)
    }

    @Test("the stored choice is followed")
    func whenStored_thenFollowed() {
        let defaults = suite()
        defaults.set(false, forKey: LinkPreviewPolicy.defaultsKey)
        #expect(!LinkPreviewPolicy.isEnabled(in: defaults, mode: .normal))
        defaults.set(true, forKey: LinkPreviewPolicy.defaultsKey)
        #expect(LinkPreviewPolicy.isEnabled(in: defaults, mode: .normal))
    }

    @Test("a test host or UI-test launch never loads a link preview, whatever the stored choice")
    func whenNotANormalLaunch_thenOff() {
        let defaults = suite()
        defaults.set(true, forKey: LinkPreviewPolicy.defaultsKey)
        for mode in [LaunchMode.hostedTests, .uiTest] {
            #expect(!LinkPreviewPolicy.isEnabled(in: defaults, mode: mode), "\(mode)")
            #expect(!LinkPreviewPolicy.isEnabled(in: suite(), mode: mode), "\(mode)")
        }
    }

    @Test("a browser's GIF is fetched only with previews on, for an eligible address, and never while locked")
    func whenFetchingAGIF_thenSwitchAddressAndLockAllMustAgree() {
        #expect(LinkPreviewPolicy.mayFetchGIF(isEnabled: true, isEligible: true, isHistoryLocked: false))
        #expect(!LinkPreviewPolicy.mayFetchGIF(isEnabled: false, isEligible: true, isHistoryLocked: false))
        #expect(!LinkPreviewPolicy.mayFetchGIF(isEnabled: true, isEligible: false, isHistoryLocked: false))
        #expect(!LinkPreviewPolicy.mayFetchGIF(isEnabled: true, isEligible: true, isHistoryLocked: true))
    }
}
