// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("FrontmostHistory")
struct FrontmostHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test("apps that were frontmost inside the window are returned")
    func whenRecordedWithinWindow_thenReturned() {
        let history = FrontmostHistory()
        history.record("com.1password.1password", at: t0)
        history.record("com.apple.Safari", at: t0 + 0.3)

        let recent = history.bundleIDs(within: 1, of: t0 + 0.5)

        #expect(Set(recent) == ["com.1password.1password", "com.apple.Safari"])
    }

    @Test("apps that stopped being frontmost before the window are not returned")
    func whenReplacedBeforeWindow_thenNotReturned() {
        let history = FrontmostHistory()
        history.record("com.1password.1password", at: t0)
        history.record("com.apple.Safari", at: t0 + 2)

        #expect(history.bundleIDs(within: 1, of: t0 + 5) == ["com.apple.Safari"])
    }

    @Test("an app that was frontmost for an hour and lost focus inside the window is still returned")
    func whenLongFrontmostAppJustLeft_thenReturned() {
        let history = FrontmostHistory()
        history.record("com.1password.1password", at: t0)
        history.record("com.apple.Safari", at: t0 + 3600)

        let recent = history.bundleIDs(within: 0.75, of: t0 + 3600.1)

        #expect(Set(recent) == ["com.1password.1password", "com.apple.Safari"])
    }

    @Test("the history stays bounded")
    func whenManyRecorded_thenBounded() {
        let history = FrontmostHistory()
        for index in 0..<500 {
            history.record("app.\(index)", at: t0 + Double(index) * 0.001)
        }

        #expect(history.bundleIDs(within: 60, of: t0 + 1).count <= 64)
    }

    @Test("an app that lost focus is excluded if a subsequent copy occurred after the switch")
    func whenCopyHappenedAfterSwitch_thenFormerAppNotReturned() {
        let history = FrontmostHistory()
        history.record("com.1password.1password", at: t0, changeCount: 10)
        history.record("com.apple.Safari", at: t0 + 0.3, changeCount: 10)

        let recentAfterCopy = history.bundleIDs(within: 1, of: t0 + 0.5, currentChangeCount: 11)
        #expect(recentAfterCopy == ["com.apple.Safari"])

        let recentBeforeCopy = history.bundleIDs(within: 1, of: t0 + 0.5, currentChangeCount: 10)
        #expect(Set(recentBeforeCopy) == ["com.1password.1password", "com.apple.Safari"])
    }
}
