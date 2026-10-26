// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Shelf suggestion policy")
struct ShelfSuggestionPolicyTests {
    private let calendar = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func context(
        isEnabled: Bool = true,
        hasOnboarded: Bool = true,
        armedDaysAgo: Int = 10,
        lastShownHoursAgo: Int? = 30,
        hotkeysLive: Bool = true,
        hasAccessibility: Bool = true,
        isHistoryLocked: Bool = false,
        isContentCovered: Bool = false,
        isStackActive: Bool = false,
        isSearching: Bool = false,
        otherBannerVisible: Bool = false
    )
    -> ShelfSuggestionContext {
        let armedAt = calendar.date(byAdding: .day, value: -armedDaysAgo, to: now)
        let lastShownAt = lastShownHoursAgo.flatMap { calendar.date(byAdding: .hour, value: -$0, to: now) }
        return ShelfSuggestionContext(
            now: now,
            isEnabled: isEnabled,
            hasOnboarded: hasOnboarded,
            armedAt: armedAt,
            lastShownAt: lastShownAt,
            hotkeysLive: hotkeysLive,
            hasAccessibility: hasAccessibility,
            isHistoryLocked: isHistoryLocked,
            isContentCovered: isContentCovered,
            isStackActive: isStackActive,
            isSearching: isSearching,
            otherBannerVisible: otherBannerVisible
        )
    }

    private func makeClip(
        id: UUID = UUID(),
        pasteCount: Int = 6,
        daysAgoUsed: Int = 1,
        isPinned: Bool = false,
        shortcutSlot: Int? = nil,
        shortcutLastUsedDaysAgo: Int? = nil,
        kind: ClipboardType = .text,
        textLength: Int = 100,
        isSensitive: Bool = false,
        isNSFW: Bool = false,
        analysisPending: Bool = false,
        expires: Bool = false,
        shelfPastesThisRun: Int = 1
    )
    -> ShelfClipFacts {
        let lastUsedAt = calendar.date(byAdding: .day, value: -daysAgoUsed, to: now) ?? now
        let shortcutLastUsedAt = shortcutLastUsedDaysAgo.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        return ShelfClipFacts(
            id: id,
            pasteCount: pasteCount,
            lastUsedAt: lastUsedAt,
            isPinned: isPinned,
            shortcutSlot: shortcutSlot,
            shortcutLastUsedAt: shortcutLastUsedAt,
            kind: kind,
            textLength: textLength,
            isSensitive: isSensitive,
            isNSFW: isNSFW,
            analysisPending: analysisPending,
            expires: expires,
            shelfPastesThisRun: shelfPastesThisRun
        )
    }

    @Test("when clip pasted at least 6 times recently with a shelf paste this run, offers lowest free shortcut")
    func whenClipPastedSixTimesRecently_thenOffersLowestFreeShortcut() {
        let clip = makeClip(pasteCount: 6, daysAgoUsed: 2, shelfPastesThisRun: 1)
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [], unavailableSlots: [])
        let result = ShelfSuggestionPolicy.next(
            context: context(),
            facts: facts,
            ledger: SuggestionLedger(serialized: "")
        )

        #expect(result == .shortcutOffer(clip: clip.id, slot: 1, pasteCount: 6, isPinned: false))
    }

    @Test("when under 6 pastes or last use older than 14 days, no offer")
    func whenUnderThreshold_thenNoOffer() {
        let lowCount = makeClip(pasteCount: 5)
        let facts1 = ShelfSuggestionFacts(clips: [lowCount], assignedSlots: [], unavailableSlots: [])
        #expect(ShelfSuggestionPolicy
            .next(context: context(), facts: facts1, ledger: SuggestionLedger(serialized: "")) == nil)

        let stale = makeClip(pasteCount: 6, daysAgoUsed: 15)
        let facts2 = ShelfSuggestionFacts(clips: [stale], assignedSlots: [], unavailableSlots: [])
        #expect(ShelfSuggestionPolicy
            .next(context: context(), facts: facts2, ledger: SuggestionLedger(serialized: "")) == nil)

        let noShelfPasteThisRun = makeClip(pasteCount: 6, daysAgoUsed: 2, shelfPastesThisRun: 0)
        let facts3 = ShelfSuggestionFacts(clips: [noShelfPasteThisRun], assignedSlots: [], unavailableSlots: [])
        #expect(ShelfSuggestionPolicy
            .next(context: context(), facts: facts3, ledger: SuggestionLedger(serialized: "")) == nil)
    }

    @Test("lowest slot assigned or unavailable skips to next free")
    func whenLowestNumbersAssignedOrUnavailable_thenOffersNextFree() {
        let clip = makeClip(pasteCount: 6)
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [1, 2], unavailableSlots: [3])
        let result = ShelfSuggestionPolicy.next(
            context: context(),
            facts: facts,
            ledger: SuggestionLedger(serialized: "")
        )
        #expect(result == .shortcutOffer(clip: clip.id, slot: 4, pasteCount: 6, isPinned: false))
    }

    @Test("when all slots 1 to 9 taken, no offer")
    func whenAllNineAssignedOrUnavailable_thenNoOffer() {
        let clip = makeClip(pasteCount: 6)
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: Set(1...9), unavailableSlots: [])
        #expect(ShelfSuggestionPolicy
            .next(context: context(), facts: facts, ledger: SuggestionLedger(serialized: "")) == nil)
    }

    @Test("when sensitive or credential or hidden, never suggested for any kind")
    func whenClipIsSensitive_thenNeverSuggested() {
        let clip = makeClip(pasteCount: 10, isSensitive: true)
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [], unavailableSlots: [])
        #expect(ShelfSuggestionPolicy
            .next(context: context(), facts: facts, ledger: SuggestionLedger(serialized: "")) == nil)
    }

    @Test("when NSFW, analysis pending, or expiring, not suggested")
    func whenClipIsNSFWOrPendingOrExpiring_thenNotSuggested() {
        let nsfw = makeClip(isNSFW: true)
        let pending = makeClip(analysisPending: true)
        let expiring = makeClip(expires: true)
        for c in [nsfw, pending, expiring] {
            let facts = ShelfSuggestionFacts(clips: [c], assignedSlots: [], unavailableSlots: [])
            #expect(ShelfSuggestionPolicy.next(
                context: context(),
                facts: facts,
                ledger: SuggestionLedger(serialized: "")
            ) == nil)
        }
    }

    @Test("text length filtering respects 1...20000; legacy 0 is eligible; image skips length check")
    func whenTextLengthChecked_thenMatchesRules() {
        let tooLong = makeClip(textLength: 20_001)
        #expect(!ShelfSuggestionPolicy.isEligibleForShortcut(tooLong))

        let legacyZero = makeClip(textLength: 0)
        #expect(ShelfSuggestionPolicy.isEligibleForShortcut(legacyZero))

        let image = makeClip(kind: .image, textLength: 0)
        #expect(ShelfSuggestionPolicy.isEligibleForShortcut(image))
    }

    @Test("when already has shortcut, no shortcut offer")
    func whenAlreadyHasShortcut_thenNoShortcutOffer() {
        let clip = makeClip(shortcutSlot: 1)
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [1], unavailableSlots: [])
        let res = ShelfSuggestionPolicy.next(context: context(), facts: facts, ledger: SuggestionLedger(serialized: ""))
        if case .shortcutOffer = res {
            Issue.record("Expected no shortcut offer for clip with shortcut")
        }
    }

    @Test("suppression rules: disabled, not onboarded, un-armed, arming quiet period, cooldown")
    func whenContextSuppressed_thenNil() {
        let clip = makeClip()
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [], unavailableSlots: [])
        let ledger = SuggestionLedger(serialized: "")

        #expect(ShelfSuggestionPolicy.next(context: context(isEnabled: false), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy.next(context: context(hasOnboarded: false), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy
            .next(context: context(armedDaysAgo: 1), facts: facts, ledger: ledger) == nil) // quiet period < 3 days
        #expect(ShelfSuggestionPolicy
            .next(context: context(lastShownHoursAgo: 12), facts: facts, ledger: ledger) == nil) // cooldown < 24h
        #expect(ShelfSuggestionPolicy.next(context: context(hotkeysLive: false), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy
            .next(context: context(hasAccessibility: false), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy
            .next(context: context(isHistoryLocked: true), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy
            .next(context: context(isContentCovered: true), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy.next(context: context(isStackActive: true), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy.next(context: context(isSearching: true), facts: facts, ledger: ledger) == nil)
        #expect(ShelfSuggestionPolicy
            .next(context: context(otherBannerVisible: true), facts: facts, ledger: ledger) == nil)
    }

    @Test("shortcut offer beats reminder beats release beats snippet")
    func whenSeveralKindsEligible_thenPriorityOrderHolds() {
        let offerClip = makeClip(id: UUID(), pasteCount: 6, shelfPastesThisRun: 1)
        let reminderClip = makeClip(
            id: UUID(),
            isPinned: true,
            shortcutSlot: 1,
            shortcutLastUsedDaysAgo: 20,
            shelfPastesThisRun: 5
        )
        let facts = ShelfSuggestionFacts(clips: [reminderClip, offerClip], assignedSlots: [1], unavailableSlots: [])
        let res = ShelfSuggestionPolicy.next(context: context(), facts: facts, ledger: SuggestionLedger(serialized: ""))
        #expect(res == .shortcutOffer(clip: offerClip.id, slot: 2, pasteCount: 6, isPinned: false))
    }

    @Test("dormant release suggested when shortcut idle 60 days and not used lately")
    func whenShortcutIdleSixtyDays_thenReleaseSuggested() {
        let clip = makeClip(
            daysAgoUsed: 20,
            isPinned: true,
            shortcutSlot: 4,
            shortcutLastUsedDaysAgo: 60,
            shelfPastesThisRun: 0
        )
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [4], unavailableSlots: [])
        let res = ShelfSuggestionPolicy.next(
            context: context(armedDaysAgo: 70),
            facts: facts,
            ledger: SuggestionLedger(serialized: "")
        )
        #expect(res == .shortcutRelease(clip: clip.id, slot: 4, idleWeeks: 8))
    }

    @Test("when shortcut used never and armed recently, grace period blocks release")
    func whenShortcutUsedNever_andArmedRecently_thenGraceBlocksRelease() {
        let clip = makeClip(
            daysAgoUsed: 20,
            isPinned: true,
            shortcutSlot: 4,
            shortcutLastUsedDaysAgo: nil,
            shelfPastesThisRun: 0
        )
        // Armed only 30 days ago (< 60 days)
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [4], unavailableSlots: [])
        let res = ShelfSuggestionPolicy.next(
            context: context(armedDaysAgo: 30),
            facts: facts,
            ledger: SuggestionLedger(serialized: "")
        )
        #expect(res == nil)
    }

    @Test("shortcut reminder offered after 5 shelf pastes this run and shortcut unused 14 days")
    func whenShelfPastedFiveTimesAndShortcutUnusedTwoWeeks_thenReminder() {
        let clip = makeClip(
            daysAgoUsed: 0,
            isPinned: true,
            shortcutSlot: 3,
            shortcutLastUsedDaysAgo: 15,
            shelfPastesThisRun: 5
        )
        let facts = ShelfSuggestionFacts(clips: [clip], assignedSlots: [3], unavailableSlots: [])
        let res = ShelfSuggestionPolicy.next(context: context(), facts: facts, ledger: SuggestionLedger(serialized: ""))
        #expect(res == .shortcutReminder(clip: clip.id, slot: 3))
    }

    @Test("when snippet eligible (pasteCount >= 8, unpinned, no slot), snippet suggested")
    func whenSnippetEligible_thenSnippetSuggested() {
        let clip = makeClip(pasteCount: 8, isPinned: false, shortcutSlot: nil, shelfPastesThisRun: 0)
        let facts = ShelfSuggestionFacts(
            clips: [clip],
            assignedSlots: Set(1...9),
            unavailableSlots: []
        ) // No free shortcuts!
        let res = ShelfSuggestionPolicy.next(context: context(), facts: facts, ledger: SuggestionLedger(serialized: ""))
        #expect(res == .snippet(clip: clip.id, pasteCount: 8))
    }
}
