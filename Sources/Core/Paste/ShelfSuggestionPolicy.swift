// SPDX-License-Identifier: MIT
import Foundation

public enum ShelfSuggestionPolicy {
    public enum Thresholds {
        public static let offerMinimumPastes = 6
        public static let offerRecencyDays = 14
        public static let offerTextLengths = 1...20_000
        public static let quietDaysAfterArming = 3
        public static let minimumHoursBetween = 24
        public static let releaseIdleDays = 60
        public static let releaseRecentUseDays = 14
        public static let reminderShelfPastes = 5
        public static let reminderQuietDays = 14
        public static let snippetMinimumPastes = 8
        public static let declinesBeforeOff = 4
        public static let ignoredShowsBeforeMute = 3
    }

    public static func isSuppressed(_ context: ShelfSuggestionContext) -> Bool {
        guard context.isEnabled,
              context.hasOnboarded,
              let armedAt = context.armedAt,
              context.hotkeysLive,
              context.hasAccessibility,
              !context.isHistoryLocked,
              !context.isContentCovered,
              !context.isStackActive,
              !context.isSearching,
              !context.otherBannerVisible else { return true }

        let calendar = Calendar.current
        if let quietEnd = calendar.date(byAdding: .day, value: Thresholds.quietDaysAfterArming, to: armedAt),
           context.now < quietEnd
        {
            return true
        }

        if let lastShown = context.lastShownAt,
           let cooldownEnd = calendar.date(byAdding: .hour, value: Thresholds.minimumHoursBetween, to: lastShown),
           context.now < cooldownEnd
        {
            return true
        }

        return false
    }

    public static func freeSlot(assigned: Set<Int>, unavailable: Set<Int>) -> Int? {
        (1...9).first { !assigned.contains($0) && !unavailable.contains($0) }
    }

    public static func isEligibleForShortcut(_ clip: ShelfClipFacts) -> Bool {
        guard !clip.isSensitive,
              !clip.isNSFW,
              !clip.analysisPending,
              !clip.expires else { return false }

        if clip.kind == .text || clip.kind == .code || clip.kind == .url {
            if clip.textLength != 0, !Thresholds.offerTextLengths.contains(clip.textLength) {
                return false
            }
        }
        return true
    }

    public static func next(
        context: ShelfSuggestionContext,
        facts: ShelfSuggestionFacts,
        ledger: SuggestionLedger
    )
    -> ShelfSuggestion? {
        if isSuppressed(context) { return nil }

        let calendar = Calendar.current
        let eligible = facts.clips.filter { clip in
            isEligibleForShortcut(clip) && !ledger.isSilenced(clip.id, currentPastes: clip.pasteCount)
        }

        if let suggestion = nextShortcutOffer(
            eligible: eligible,
            facts: facts,
            context: context,
            ledger: ledger,
            calendar: calendar
        ) {
            return suggestion
        }

        if let suggestion = nextShortcutReminder(
            eligible: eligible,
            context: context,
            ledger: ledger,
            calendar: calendar
        ) {
            return suggestion
        }

        if let suggestion = nextShortcutRelease(
            eligible: eligible,
            context: context,
            ledger: ledger,
            calendar: calendar
        ) {
            return suggestion
        }

        return nextSnippet(
            eligible: eligible,
            context: context,
            ledger: ledger,
            calendar: calendar
        )
    }

    private static func nextShortcutOffer(
        eligible: [ShelfClipFacts],
        facts: ShelfSuggestionFacts,
        context: ShelfSuggestionContext,
        ledger: SuggestionLedger,
        calendar: Calendar
    )
    -> ShelfSuggestion? {
        guard let slot = freeSlot(assigned: facts.assignedSlots, unavailable: facts.unavailableSlots) else {
            return nil
        }
        let cutoff = calendar.date(byAdding: .day, value: -Thresholds.offerRecencyDays, to: context.now) ?? .distantPast
        let candidates = eligible.filter { clip in
            clip.shortcutSlot == nil
                && clip.pasteCount >= Thresholds.offerMinimumPastes
                && clip.lastUsedAt >= cutoff
                && clip.shelfPastesThisRun >= 1
                && !ledger.isResolved(.shortcutOffer, clip.id)
        }.sorted {
            if $0.pasteCount != $1.pasteCount { return $0.pasteCount > $1.pasteCount }
            if $0.lastUsedAt != $1.lastUsedAt { return $0.lastUsedAt > $1.lastUsedAt }
            return $0.id.uuidString < $1.id.uuidString
        }

        guard let best = candidates.first else { return nil }
        return .shortcutOffer(clip: best.id, slot: slot, pasteCount: best.pasteCount, isPinned: best.isPinned)
    }

    private static func nextShortcutReminder(
        eligible: [ShelfClipFacts],
        context: ShelfSuggestionContext,
        ledger: SuggestionLedger,
        calendar: Calendar
    )
    -> ShelfSuggestion? {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -Thresholds.reminderQuietDays,
            to: context.now
        ) ?? .distantPast
        let candidates = eligible.filter { clip in
            guard clip.shortcutSlot != nil else { return false }
            let idleEnough = clip.shortcutLastUsedAt == nil || (clip.shortcutLastUsedAt ?? .distantFuture) <= cutoff
            return clip.shelfPastesThisRun >= Thresholds.reminderShelfPastes
                && idleEnough
                && !ledger.isResolved(.shortcutReminder, clip.id)
        }.sorted {
            if $0.shelfPastesThisRun != $1.shelfPastesThisRun { return $0.shelfPastesThisRun > $1.shelfPastesThisRun }
            if $0.lastUsedAt != $1.lastUsedAt { return $0.lastUsedAt > $1.lastUsedAt }
            return $0.id.uuidString < $1.id.uuidString
        }

        guard let best = candidates.first, let slot = best.shortcutSlot else { return nil }
        return .shortcutReminder(clip: best.id, slot: slot)
    }

    private static func nextShortcutRelease(
        eligible: [ShelfClipFacts],
        context: ShelfSuggestionContext,
        ledger: SuggestionLedger,
        calendar: Calendar
    )
    -> ShelfSuggestion? {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -Thresholds.releaseRecentUseDays,
            to: context.now
        ) ?? .distantPast
        let candidates = eligible.filter { clip in
            guard clip.shortcutSlot != nil, clip.isPinned else { return false }
            guard clip.lastUsedAt <= cutoff else { return false }
            let lastUse = [clip.shortcutLastUsedAt, context.armedAt].compactMap(\.self).max() ?? .distantPast
            guard let idleThreshold = calendar.date(
                byAdding: .day,
                value: Thresholds.releaseIdleDays,
                to: lastUse
            ) else { return false }
            return context.now >= idleThreshold && !ledger.isResolved(.shortcutRelease, clip.id)
        }.sorted {
            let u0 = [$0.shortcutLastUsedAt, context.armedAt].compactMap(\.self).max() ?? .distantPast
            let u1 = [$1.shortcutLastUsedAt, context.armedAt].compactMap(\.self).max() ?? .distantPast
            if u0 != u1 { return u0 < u1 }
            return $0.id.uuidString < $1.id.uuidString
        }

        guard let best = candidates.first, let slot = best.shortcutSlot else { return nil }
        let lastUse = [best.shortcutLastUsedAt, context.armedAt].compactMap(\.self).max() ?? .distantPast
        let idleDays = calendar.dateComponents([.day], from: lastUse, to: context.now).day ?? Thresholds
            .releaseIdleDays
        let idleWeeks = max(8, idleDays / 7)
        return .shortcutRelease(clip: best.id, slot: slot, idleWeeks: idleWeeks)
    }

    private static func nextSnippet(
        eligible: [ShelfClipFacts],
        context: ShelfSuggestionContext,
        ledger: SuggestionLedger,
        calendar: Calendar
    )
    -> ShelfSuggestion? {
        let cutoff = calendar.date(byAdding: .day, value: -Thresholds.offerRecencyDays, to: context.now) ?? .distantPast
        let candidates = eligible.filter { clip in
            clip.shortcutSlot == nil
                && !clip.isPinned
                && clip.pasteCount >= Thresholds.snippetMinimumPastes
                && clip.lastUsedAt >= cutoff
                && SnippetSuggester.isEligible(
                    pasteCount: clip.pasteCount,
                    isPinned: clip.isPinned,
                    isTextual: clip.kind == .text || clip.kind == .code,
                    isSecret: clip.isSensitive,
                    length: clip.textLength
                )
                && !ledger.isResolved(.snippet, clip.id)
        }.sorted {
            if $0.pasteCount != $1.pasteCount { return $0.pasteCount > $1.pasteCount }
            if $0.lastUsedAt != $1.lastUsedAt { return $0.lastUsedAt > $1.lastUsedAt }
            return $0.id.uuidString < $1.id.uuidString
        }

        guard let best = candidates.first else { return nil }
        return .snippet(clip: best.id, pasteCount: best.pasteCount)
    }
}
