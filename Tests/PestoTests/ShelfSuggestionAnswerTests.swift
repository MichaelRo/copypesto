// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

private final class SpokenLog: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func add(_ message: String) {
        lock.withLock { messages.append(message) }
    }

    var all: [String] {
        lock.withLock { messages }
    }
}

extension HostedGlobals {
    @Suite("Shelf suggestion answers", .serialized)
    @MainActor
    struct ShelfSuggestionAnswerTests {
        private func resetSettings() {
            AppDefaults.store.removeObject(forKey: Setting.shelfSuggestionsArmedAt.name)
            AppDefaults.store.removeObject(forKey: Setting.shelfSuggestionsLastShownAt.name)
            AppDefaults.store.removeObject(forKey: Setting.shelfSuggestionDeclines.name)
            AppDefaults.store.removeObject(forKey: Setting.shelfSuggestionsEnabled.name)
            AppDefaults.store.removeObject(forKey: Setting.shelfSuggestionLedger.name)
            AppDefaults.store.removeObject(forKey: Setting.hasOnboarded.name)
        }

        private func makeState() -> AppState {
            let state = AppState()
            state.hasAccessibilityPermission = true
            AppDefaults.store.set(true, for: Setting.hasOnboarded)
            return state
        }

        @Test("evaluating when eligible sets last shown date and does not duplicate")
        func whenOpened_thenSetsLastShownAndNoSecondOne() {
            defer { resetSettings() }
            let state = makeState()
            let clipID = UUID()
            let armed = Date.now.addingTimeInterval(-86_400 * 10)
            AppDefaults.store.set(Int(armed.timeIntervalSince1970), for: Setting.shelfSuggestionsArmedAt)

            let facts = ShelfSuggestionFacts(
                clips: [
                    ShelfClipFacts(
                        id: clipID,
                        pasteCount: 7,
                        lastUsedAt: Date.now,
                        isPinned: false,
                        shortcutSlot: nil,
                        shortcutLastUsedAt: nil,
                        kind: .text,
                        textLength: 100,
                        shelfPastesThisRun: 1
                    )
                ],
                assignedSlots: [],
                unavailableSlots: []
            )
            state.shelfPasteTally[clipID] = 1
            state.shelfSuggestionFacts = facts

            state.evaluateShelfSuggestion()

            #expect(state.shelfSuggestion != nil)
            #expect(state.shelfSuggestion?.targetClipID == clipID)
            #expect(state.shelfSuggestion?.targetSlot == 1)
            #expect(AppDefaults.store.value(for: Setting.shelfSuggestionsLastShownAt) > 0)
        }

        @Test("declining 4 times turns feature off and shows notice")
        func whenDeclinedFourTimes_thenFeatureOffAndNoticeShown() {
            defer { resetSettings() }
            let state = makeState()
            let clipID = UUID()
            AppDefaults.store.set(3, for: Setting.shelfSuggestionDeclines)
            state.shelfSuggestion = ShelfSuggestionPresentation(
                suggestion: .shortcutOffer(clip: clipID, slot: 1, pasteCount: 6, isPinned: false),
                isNotice: false
            )

            state.declineShelfSuggestion()

            #expect(AppDefaults.store.value(for: Setting.shelfSuggestionsEnabled) == false)
            #expect(state.shelfSuggestion?.isNotice == true)
        }

        @Test("accepting a shortcut offer resets the decline streak and announces")
        func whenAcceptedBetweenDeclines_thenStreakResets() async {
            defer { resetSettings() }
            let state = makeState()
            let clipID = UUID()
            AppDefaults.store.set(2, for: Setting.shelfSuggestionDeclines)
            state.shelfSuggestion = ShelfSuggestionPresentation(
                suggestion: .shortcutOffer(clip: clipID, slot: 2, pasteCount: 6, isPinned: false),
                isNotice: false
            )

            let spoken = SpokenLog()
            let originalAnnounce = Announcer.speak
            Announcer.speak = { msg, _ in spoken.add(msg) }
            defer { Announcer.speak = originalAnnounce }

            state.acceptShelfSuggestion()
            try? await Task.sleep(for: .milliseconds(50))

            #expect(AppDefaults.store.value(for: Setting.shelfSuggestionDeclines) == 0)
        }

        @Test("acknowledging a reminder leaves the decline streak untouched")
        func whenGotIt_thenStreakUntouched() {
            defer { resetSettings() }
            let state = makeState()
            let clipID = UUID()
            AppDefaults.store.set(2, for: Setting.shelfSuggestionDeclines)
            state.shelfSuggestion = ShelfSuggestionPresentation(
                suggestion: .shortcutReminder(clip: clipID, slot: 1),
                isNotice: false
            )

            state.acknowledgeShelfSuggestion()

            #expect(state.shelfSuggestion == nil)
            #expect(AppDefaults.store.value(for: Setting.shelfSuggestionDeclines) == 2)
        }

        @Test("locking history or suppressing clears active shelf suggestion")
        func whenLockEngagesWhileShown_thenCleared() {
            defer { resetSettings() }
            let state = makeState()
            let clipID = UUID()
            state.shelfSuggestion = ShelfSuggestionPresentation(
                suggestion: .shortcutOffer(clip: clipID, slot: 1, pasteCount: 6, isPinned: false),
                isNotice: false
            )

            state.suppressShelfSuggestions()

            #expect(state.shelfSuggestion == nil)
            #expect(state.shelfSuggestionDwellTask == nil)
        }

        @Test("closing shelf notes shown in suggestion ledger")
        func whenShelfClosesUnanswered_thenIgnoredShowCounted() {
            defer { resetSettings() }
            let state = makeState()
            let clipID = UUID()
            state.shelfSuggestion = ShelfSuggestionPresentation(
                suggestion: .shortcutOffer(clip: clipID, slot: 1, pasteCount: 6, isPinned: false),
                isNotice: false
            )

            state.shelfDidClose()

            let ledger = SuggestionLedger(serialized: AppDefaults.store.value(for: Setting.shelfSuggestionLedger))
            #expect(ledger.shows(.shortcutOffer, clipID) == 1)
        }

        @Test("accepting snippet suggestion opens settings with clip id")
        func whenSnippetAccepted_thenPendingSeedAndSettingsOpened() {
            defer { resetSettings() }
            let state = makeState()
            let clipID = UUID()
            var settingsOpened = 0
            state.openSettingsFromOverlay = { settingsOpened += 1 }
            state.shelfSuggestion = ShelfSuggestionPresentation(
                suggestion: .snippet(clip: clipID, familySize: 3),
                isNotice: false
            )

            state.acceptShelfSuggestion()

            #expect(state.pendingSnippetSeed == clipID)
            #expect(state.pendingSettingsSection == SettingsSection.snippets.rawValue)
            #expect(settingsOpened == 1)
        }
    }
}
