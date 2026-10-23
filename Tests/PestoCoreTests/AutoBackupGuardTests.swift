// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Automatic backup guard")
struct AutoBackupGuardTests {
    @Test("a store that is only in memory is never backed up")
    func whenStoreIsNotOnDisk_thenRefused() {
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: false,
            unreadable: 0,
            clips: 1,
            lastClips: 500,
            allowShrink: true
        )
            == .storeNotOnDisk)
    }

    @Test("a history with clips this Mac cannot open is never backed up, even when asked")
    func whenClipsAreUnreadable_thenRefused() {
        #expect(AutoBackupGuard.refusal(storeIsOnDisk: true, unreadable: 3, clips: 40, lastClips: 40, allowShrink: true)
            == .unreadableClips(3))
    }

    @Test("a history under half the last backup is refused unless the person confirms")
    func whenMuchSmaller_thenRefusedUnlessAllowed() {
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: true,
            unreadable: 0,
            clips: 9,
            lastClips: 100,
            allowShrink: false
        )
            == .muchSmaller(now: 9, before: 100))
        #expect(AutoBackupGuard.refusal(storeIsOnDisk: true, unreadable: 0, clips: 9, lastClips: 100, allowShrink: true)
            == nil)
    }

    @Test("an ordinary change goes through")
    func whenHistoryIsSimilar_thenAllowed() {
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: true,
            unreadable: 0,
            clips: 60,
            lastClips: 100,
            allowShrink: false
        )
            == nil)
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: true,
            unreadable: 0,
            clips: 0,
            lastClips: nil,
            allowShrink: false
        )
            == nil)
    }

    @Test("a small history is not judged by the shrink rule")
    func whenLastBackupWasSmall_thenShrinkRuleDoesNotApply() {
        #expect(AutoBackupGuard.refusal(storeIsOnDisk: true, unreadable: 0, clips: 1, lastClips: 8, allowShrink: false)
            == nil)
    }

    @Test("a backup kept on purpose after Clear Everything is not replaced until the person says so")
    func whenPausedAfterClear_thenRefusedUnlessAllowed() {
        #expect(
            AutoBackupGuard.refusal(
                storeIsOnDisk: true, unreadable: 0, clips: 0, lastClips: 3, allowShrink: false, pausedAfterClear: true
            ) == .keptAfterClear
        )
        #expect(
            AutoBackupGuard.refusal(
                storeIsOnDisk: true, unreadable: 0, clips: 0, lastClips: 3, allowShrink: true, pausedAfterClear: true
            ) == nil
        )
    }

    @Test("a file in the folder that this Mac's key does not open is never replaced, even when asked")
    func whenTheFileIsUnderAnotherKey_thenRefused() {
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: true, unreadable: 0, clips: 40, lastClips: 40, allowShrink: true,
            fileUsesAnotherKey: true
        ) == .anotherKeyInFolder)
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: true, unreadable: 0, clips: 40, lastClips: 40, allowShrink: true,
            fileUsesAnotherKey: false
        ) == nil)
    }

    @Test("the baseline only rises, so a history that shrinks a little at a time is still caught")
    func whenHistoryShrinksGradually_thenTheBaselineHolds() {
        var anchor: Int? = 100
        for clips in [90, 75, 60, 52] {
            #expect(AutoBackupGuard.refusal(
                storeIsOnDisk: true, unreadable: 0, clips: clips, lastClips: anchor, allowShrink: false
            ) == nil)
            anchor = AutoBackupGuard.nextBaseline(previous: anchor, written: clips, confirmed: false)
        }

        #expect(anchor == 100)
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: true, unreadable: 0, clips: 45, lastClips: anchor, allowShrink: false
        ) == .muchSmaller(now: 45, before: 100))
    }

    @Test("the baseline follows a growing history")
    func whenHistoryGrows_thenTheBaselineRises() {
        #expect(AutoBackupGuard.nextBaseline(previous: 100, written: 140, confirmed: false) == 140)
        #expect(AutoBackupGuard.nextBaseline(previous: nil, written: 7, confirmed: false) == 7)
    }

    @Test("a smaller history the person confirmed becomes the new baseline")
    func whenShrinkIsConfirmed_thenTheBaselineDrops() {
        #expect(AutoBackupGuard.nextBaseline(previous: 100, written: 30, confirmed: true) == 30)
    }

    @Test("clips removed on purpose lower the baseline by that many, never below zero, and never invent one")
    func lowerBaseline_followsWhatWasRemovedOnPurpose() {
        let defaults = ThrowawayDefaults.make()
        let settings = AutoBackupSettings(defaults: defaults)

        settings.lowerBaseline(by: 10)
        #expect(settings.lastClipCount == nil)

        settings.lastClipCount = 100
        settings.lowerBaseline(by: 60)
        #expect(settings.lastClipCount == 40)
        settings.lowerBaseline(by: 500)
        #expect(settings.lastClipCount == 0)
        settings.lowerBaseline(by: -5)
        #expect(settings.lastClipCount == 0)
    }

    @Test("a retention sweep that removed most of the history no longer stops the next backup")
    func afterARetentionSweep_theNextBackupIsNotRefused() {
        let defaults = ThrowawayDefaults.make()
        let settings = AutoBackupSettings(defaults: defaults)
        settings.lastClipCount = 100

        settings.lowerBaseline(by: 70)
        let refusal = AutoBackupGuard.refusal(
            storeIsOnDisk: true, unreadable: 0, clips: 30, lastClips: settings.lastClipCount, allowShrink: false
        )

        #expect(refusal == nil)
        #expect(AutoBackupGuard.refusal(
            storeIsOnDisk: true, unreadable: 0, clips: 30, lastClips: 100, allowShrink: false
        ) != nil, "an unexplained drop is still refused")
    }
}
