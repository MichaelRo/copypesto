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
    final class ShelfSuggestionAnswerTests {
        private let previousArmed: Int
        private let previousLastShown: Int
        private let previousDeclines: Int
        private let previousEnabled: Bool
        private let previousLedger: String
        private let previousOnboarded: Bool

        init() {
            previousArmed = AppDefaults.store.value(for: Setting.shelfSuggestionsArmedAt)
            previousLastShown = AppDefaults.store.value(for: Setting.shelfSuggestionsLastShownAt)
            previousDeclines = AppDefaults.store.value(for: Setting.shelfSuggestionDeclines)
            previousEnabled = AppDefaults.store.value(for: Setting.shelfSuggestionsEnabled)
            previousLedger = AppDefaults.store.value(for: Setting.shelfSuggestionLedger)
            previousOnboarded = AppDefaults.store.value(for: Setting.hasOnboarded)
        }

        deinit {
            AppDefaults.store.set(previousArmed, for: Setting.shelfSuggestionsArmedAt)
            AppDefaults.store.set(previousLastShown, for: Setting.shelfSuggestionsLastShownAt)
            AppDefaults.store.set(previousDeclines, for: Setting.shelfSuggestionDeclines)
            AppDefaults.store.set(previousEnabled, for: Setting.shelfSuggestionsEnabled)
            AppDefaults.store.set(previousLedger, for: Setting.shelfSuggestionLedger)
            AppDefaults.store.set(previousOnboarded, for: Setting.hasOnboarded)
        }

        private func makeState() -> AppState {
            let state = AppState()
            state.hasAccessibilityPermission = true
            AppDefaults.store.set(true, for: Setting.hasOnboarded)
            return state
        }

        @Test("evaluating when eligible sets last shown date and does not duplicate")
        func whenOpened_thenSetsLastShownAndNoSecondOne() {
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
            let state = makeState()
            let clipID = UUID()
            var settingsOpened = 0
            state.openSettingsFromOverlay = { settingsOpened += 1 }
            state.shelfSuggestion = ShelfSuggestionPresentation(
                suggestion: .snippet(clip: clipID, pasteCount: 8),
                isNotice: false
            )

            state.acceptShelfSuggestion()

            #expect(state.pendingSnippetSeed == clipID)
            #expect(state.pendingSettingsSection == SettingsSection.snippets.rawValue)
            #expect(settingsOpened == 1)
        }
    }
}
