// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ShelfEmptyState")
struct ShelfEmptyStateTests {
    private func state(
        hasStorage: Bool = true,
        visibleCount: Int = 0,
        isSearching: Bool = false,
        inCollection: Bool = false,
        selectedAppName: String? = nil,
        isPaused: Bool = false,
        captureBlocked: Bool = false
    )
    -> ShelfEmptyState? {
        ShelfEmptyState.evaluate(.init(
            hasStorage: hasStorage,
            visibleCount: visibleCount,
            isSearching: isSearching,
            inCollection: inCollection,
            selectedAppName: selectedAppName,
            isPaused: isPaused,
            captureBlocked: captureBlocked
        ))
    }

    @Test("cards on screen means no empty state")
    func whenCardsVisible_thenNil() {
        #expect(state(visibleCount: 3) == nil)
    }

    @Test("an empty history is the plain no-clips state")
    func whenNothingCopied_thenNoClips() {
        #expect(state() == .noClips)
    }

    @Test("a search with no matches says so")
    func whenSearchFindsNothing_thenNoResults() {
        #expect(state(isSearching: true) == .noResults)
    }

    @Test("an empty collection is distinct from an empty history")
    func whenCollectionEmpty_thenEmptyCollection() {
        #expect(state(inCollection: true) == .emptyCollection)
    }

    @Test("an empty app filter says no clips from that app")
    func whenAppFilterEmpty_thenEmptyAppFilter() {
        #expect(state(selectedAppName: "Safari") == .emptyAppFilter(appName: "Safari"))
    }

    @Test("while paused the empty shelf explains why nothing arrives")
    func whenPausedAndEmpty_thenPaused() {
        #expect(state(isPaused: true) == .paused)
    }

    @Test("blocked clipboard access explains why nothing arrives")
    func whenCaptureBlockedAndEmpty_thenCaptureBlocked() {
        #expect(state(captureBlocked: true) == .captureBlocked)
    }

    @Test("missing storage wins over everything")
    func whenNoStorage_thenStorageUnavailable() {
        #expect(state(hasStorage: false, isSearching: true, isPaused: true) == .storageUnavailable)
    }

    @Test("a search result count beats pause and blocked hints")
    func whenSearching_thenSearchWinsOverPause() {
        #expect(state(isSearching: true, isPaused: true, captureBlocked: true) == .noResults)
    }

    @Test("a state with a way out offers it: blocked access opens Privacy settings, a paused shelf resumes capturing")
    func whenStateHasAFix_thenItOffersTheAction() {
        #expect(ShelfEmptyState.captureBlocked.action == .openPrivacySettings)
        #expect(ShelfEmptyState.paused.action == .resumeCapturing)
    }

    @Test("a state with nothing to press offers no action")
    func whenNothingToDo_thenNoAction() {
        let noActionStates: [ShelfEmptyState] = [
            .noClips, .noResults, .emptyCollection, .emptyAppFilter(appName: "Safari"), .storageUnavailable
        ]
        for state in noActionStates {
            #expect(state.action == nil)
        }
    }
}
