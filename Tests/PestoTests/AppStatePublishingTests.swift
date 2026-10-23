// SPDX-License-Identifier: MIT
import Observation
import Testing
@testable import Pesto

private final class ChangeCounter: @unchecked Sendable {
    var changes = 0
}

extension HostedGlobals {
    @Suite("App state only notifies a view about what it reads, and only on a change")
    @MainActor
    struct AppStatePublishingTests {
        /// Reads `read` once, the way a view's body does, and counts the first change to anything it read.
        private func watch(_ read: @MainActor () -> Void) -> ChangeCounter {
            let counter = ChangeCounter()
            withObservationTracking(read) { counter.changes += 1 }
            return counter
        }

        @Test("rechecking Accessibility with nothing changed notifies nothing")
        func whenAccessibilityIsUnchanged_thenNothingIsNotified() async {
            let state = AppState()
            let counter = watch { _ = state.hasAccessibilityPermission }

            state.recheckAccessibility()
            state.recheckAccessibility()
            await Task.yield()

            #expect(counter.changes == 0)
        }

        @Test("a view that reads the search text is not redrawn by a drag starting")
        func whenAnotherPropertyChanges_thenAReaderOfSearchTextIsNotNotified() async {
            let state = AppState()
            let counter = watch { _ = state.searchText }

            state.isDragging = true
            state.isOverlayVisible = true
            state.isCapturingPaused = true
            await Task.yield()
            #expect(counter.changes == 0)

            state.searchText = "pesto"
            await Task.yield()
            #expect(counter.changes == 1)
        }

        @Test("setting the shelf hidden calls the paste hook, and showing it does not")
        func whenTheShelfIsHidden_thenTheHookRuns() {
            let state = AppState()
            var hidden = 0
            state.onOverlayHidden = { hidden += 1 }

            state.isOverlayVisible = true
            #expect(hidden == 0)
            state.isOverlayVisible = false
            #expect(hidden == 1)
        }

        @Test("an AI result and the loading state reach their hooks")
        func whenAIChanges_thenTheHooksRun() {
            let state = AppState()
            var loading = 0
            state.onAILoading = { loading += 1 }

            state.aiIsLoading = true
            state.aiIsLoading = false

            #expect(loading == 1)
        }
    }
}
