// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

extension AppState {
    func refreshShelfSuggestionFacts() async {
        if AppDefaults.store.value(for: Setting.hasOnboarded),
           AppDefaults.store.value(for: Setting.shelfSuggestionsArmedAt) == 0
        {
            AppDefaults.store.set(Int(Date.now.timeIntervalSince1970), for: Setting.shelfSuggestionsArmedAt)
        }

        let facts: ShelfSuggestionFacts? = if let provider = shelfFactsProvider {
            await provider()
        } else {
            try? await storageService?.shelfSuggestionFacts(unavailableSlots: hotkeyController.unavailableSlots)
        }

        if let facts { shelfSuggestionFacts = facts }
        await pruneShelfSuggestionLedger()
    }

    private func pruneShelfSuggestionLedger() async {
        guard let storageService else { return }
        var ledger = SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))
        let ids = ledger.clipIDs
        guard !ids.isEmpty, let existing = try? await storageService.existingClipIDs(among: ids),
              existing.count < ids.count else { return }
        ledger.prune(existingClipIDs: existing)
        AppDefaults.store.set(ledger.serialized, for: Setting.shelfSuggestionLedger)
    }

    func shelfDidOpen() {
        shelfSuggestionDwellTask?.cancel()
        shelfSuggestionDwellTask = nil

        checkAndApplyBiometricLock()
        if isHistoryLocked ||
            isContentCovered(screenSharingPrivacy: AppDefaults.store.value(for: Setting.screenSharingPrivacy)) ||
            isSearching || otherBannerVisible
        {
            suppressShelfSuggestions()
            return
        }

        shelfSuggestionDwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            await self.refreshShelfSuggestionFacts()
            guard !Task.isCancelled else { return }
            self.evaluateShelfSuggestion()
        }
    }

    func shelfDidClose() {
        shelfSuggestionDwellTask?.cancel()
        shelfSuggestionDwellTask = nil

        if let suggestion = shelfSuggestion?.suggestion {
            var ledger = SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))
            let pastes = shelfSuggestionFacts?.clips.first(where: { $0.id == suggestion.clipID })?.pasteCount ?? 0
            ledger.noteShown(suggestion.kind, suggestion.clipID, pastes: pastes, now: Date())
            AppDefaults.store.set(ledger.serialized, for: Setting.shelfSuggestionLedger)
        }
        shelfSuggestion = nil

        Task { [weak self] in
            await self?.refreshShelfSuggestionFacts()
        }
    }

    private var otherBannerVisible: Bool {
        !importOffer.isEmpty || lastUserError != nil || !hasAccessibilityPermission
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func evaluateShelfSuggestion() {
        checkAndApplyBiometricLock()
        guard !isHistoryLocked,
              !isContentCovered(screenSharingPrivacy: AppDefaults.store.value(for: Setting.screenSharingPrivacy)),
              !isSearching,
              !otherBannerVisible else
        {
            suppressShelfSuggestions()
            return
        }

        guard var facts = shelfSuggestionFacts else { return }

        // Merge memory tally
        var mergedClips = facts.clips
        for i in mergedClips.indices {
            let tally = shelfPasteTally[mergedClips[i].id, default: 0]
            mergedClips[i].shelfPastesThisRun = max(mergedClips[i].shelfPastesThisRun, tally)
        }
        facts = ShelfSuggestionFacts(
            clips: mergedClips,
            assignedSlots: facts.assignedSlots,
            unavailableSlots: facts.unavailableSlots
        )

        let context = makeShelfSuggestionContext()

        let ledger = SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))

        guard let suggestion = ShelfSuggestionPolicy.next(context: context, facts: facts, ledger: ledger) else {
            return
        }

        AppDefaults.store.set(Int(Date.now.timeIntervalSince1970), for: Setting.shelfSuggestionsLastShownAt)

        shelfSuggestion = ShelfSuggestionPresentation(suggestion: suggestion)
        announceSuggestion(suggestion)
    }

    private func makeShelfSuggestionContext() -> ShelfSuggestionContext {
        let armedSeconds = AppDefaults.store.value(for: Setting.shelfSuggestionsArmedAt)
        let armedAt = armedSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(armedSeconds)) : nil

        let lastShownSeconds = AppDefaults.store.value(for: Setting.shelfSuggestionsLastShownAt)
        let lastShownAt = lastShownSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(lastShownSeconds)) : nil

        return ShelfSuggestionContext(
            now: .now,
            isEnabled: AppDefaults.store.value(for: Setting.shelfSuggestionsEnabled),
            hasOnboarded: AppDefaults.store.value(for: Setting.hasOnboarded),
            armedAt: armedAt,
            lastShownAt: lastShownAt,
            hotkeysLive: LaunchMode.current.usesSystemIntegrations || LaunchMode.current == .hostedTests
                || RuntimeConfiguration.current.suggestionsLive,
            hasAccessibility: hasAccessibilityPermission,
            isHistoryLocked: isHistoryLocked,
            isContentCovered: isContentCovered(screenSharingPrivacy: AppDefaults.store
                .value(for: Setting.screenSharingPrivacy)),
            isStackActive: activeStack != nil,
            isSearching: isSearching,
            otherBannerVisible: otherBannerVisible
        )
    }

    private func announceSuggestion(_ suggestion: ShelfSuggestion) {
        let announcement: String = switch suggestion {
        case let .shortcutOffer(_, slot, pasteCount, isPinned):
            isPinned
                ? "Shortcut suggestion. You have pasted this clip \(pasteCount) times. "
                + "Paste it from any app with Control \(slot)?"
                : "Shortcut suggestion. You have pasted this clip \(pasteCount) times. "
                + "Pin it and paste it from any app with Control \(slot)?"
        case let .shortcutReminder(_, slot):
            "Tip. You pasted this clip from the shelf. Control \(slot) pastes it from any app."
        case let .shortcutRelease(_, slot, weeks):
            "Shortcut suggestion. You have not used Control \(slot) in \(weeks) weeks. "
                + "Remove the shortcut? The clip stays pinned."
        case .snippet:
            "Suggestion. These clips look alike. Make one snippet with a fill-in for what changes?"
        }
        Announcer.announce(announcement)
    }

    func acceptShelfSuggestion() {
        guard let suggestion = shelfSuggestion?.suggestion else { return }
        shelfSuggestion = nil

        var ledger = SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))

        switch suggestion {
        case let .snippet(clip, _):
            ledger.resolve(.snippet, clip, as: .accepted)
            AppDefaults.store.set(ledger.serialized, for: Setting.shelfSuggestionLedger)
            AppDefaults.store.set(0, for: Setting.shelfSuggestionDeclines)
            pendingSnippetSeed = clip
            pendingSettingsSection = SettingsSection.snippets.rawValue
            close()
            openSettingsFromOverlay?()
            return
        case .shortcutReminder:
            acknowledgeShelfSuggestion()
            return
        default:
            break
        }

        let beforeUndoCount = storageService?.undoHistory.recordedCount ?? 0

        Task { [weak self] in
            guard let self else { return }
            switch suggestion {
            case let .shortcutOffer(clip, slot, _, _):
                let result = if let service = self.storageService {
                    try? await service.assignFreeHotkeySlot(slot, to: clip)
                } else {
                    AssignFreeSlotResult.assigned
                }
                if result == .assigned {
                    var updatedLedger = SuggestionLedger(serialized: AppDefaults.store
                        .value(for: Setting.shelfSuggestionLedger))
                    updatedLedger.resolve(.shortcutOffer, clip, as: .accepted)
                    AppDefaults.store.set(updatedLedger.serialized, for: Setting.shelfSuggestionLedger)
                    AppDefaults.store.set(0, for: Setting.shelfSuggestionDeclines)
                    Announcer.announce("Control \(slot) set. The clip is pinned.")
                    self.offerUndo(since: beforeUndoCount)
                } else if result == .slotTaken {
                    self.showUserMessage(String(localized: "That shortcut was just taken."))
                }
            case let .shortcutRelease(clip, slot, _):
                _ = try? await self.storageService?.assignHotkeySlot(nil, to: clip)
                var updatedLedger = SuggestionLedger(serialized: AppDefaults.store
                    .value(for: Setting.shelfSuggestionLedger))
                updatedLedger.resolve(.shortcutRelease, clip, as: .accepted)
                AppDefaults.store.set(updatedLedger.serialized, for: Setting.shelfSuggestionLedger)
                AppDefaults.store.set(0, for: Setting.shelfSuggestionDeclines)
                Announcer.announce("Control \(slot) is free.")
                self.offerUndo(since: beforeUndoCount)
            case .shortcutReminder, .snippet:
                break
            }
        }
    }

    func declineShelfSuggestion() {
        guard let suggestion = shelfSuggestion?.suggestion else {
            shelfSuggestion = nil
            return
        }

        var ledger = SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))
        let currentPastes = shelfSuggestionFacts?.clips.first(where: { $0.id == suggestion.clipID })?.pasteCount ?? 0
        ledger.resolve(suggestion.kind, suggestion.clipID, as: .declined(atPasteCount: currentPastes), now: Date())
        AppDefaults.store.set(ledger.serialized, for: Setting.shelfSuggestionLedger)

        let declines = AppDefaults.store.value(for: Setting.shelfSuggestionDeclines) + 1
        AppDefaults.store.set(declines, for: Setting.shelfSuggestionDeclines)

        if declines >= ShelfSuggestionPolicy.Thresholds.declinesBeforeOff {
            AppDefaults.store.set(false, for: Setting.shelfSuggestionsEnabled)
            shelfSuggestion = .offNotice
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                if self?.shelfSuggestion?.isNotice == true {
                    self?.shelfSuggestion = nil
                }
            }
        } else {
            shelfSuggestion = nil
        }
    }

    func acknowledgeShelfSuggestion() {
        guard let suggestion = shelfSuggestion?.suggestion else {
            shelfSuggestion = nil
            return
        }
        var ledger = SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))
        ledger.resolve(suggestion.kind, suggestion.clipID, as: .acknowledged)
        AppDefaults.store.set(ledger.serialized, for: Setting.shelfSuggestionLedger)
        shelfSuggestion = nil
    }

    func noteShortcutUsed(id: UUID) {
        Task { [weak self] in
            try? await self?.storageService?.noteShortcutUsed(id: id)
            await self?.refreshShelfSuggestionFacts()
        }
    }

    func clearShelfSuggestions() {
        suppressShelfSuggestions()
        shelfPasteTally.removeAll()
        AppDefaults.store.set("", for: Setting.shelfSuggestionLedger)
        AppDefaults.store.set(0, for: Setting.shelfSuggestionDeclines)
    }

    func resetShelfSuggestions() {
        clearShelfSuggestions()
        AppDefaults.store.set(0, for: Setting.shelfSuggestionsArmedAt)
        Task { [weak self] in
            await self?.refreshShelfSuggestionFacts()
        }
    }

    func suppressShelfSuggestions() {
        shelfSuggestion = nil
        shelfSuggestionDwellTask?.cancel()
        shelfSuggestionDwellTask = nil
    }
}
