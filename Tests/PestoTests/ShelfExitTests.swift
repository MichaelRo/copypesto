// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

@Suite("Closing the shelf says why")
@MainActor
struct ShelfExitTests {
    private func state() -> (AppState, Counter) {
        let state = AppState()
        let counter = Counter()
        state.onOverlayHidden = { counter.hides += 1 }
        state.isOverlayVisible = true
        counter.hides = 0
        return (state, counter)
    }

    final class Counter {
        var hides = 0
    }

    @Test("a dismissal closes the shelf once and leaves no exit behind")
    func whenDismissed_thenOneHideAndNoPaste() {
        let (state, counter) = state()

        state.close()

        #expect(!state.isOverlayVisible)
        #expect(counter.hides == 1)
        guard case .dismissed = state.takePendingExit() else {
            Issue.record("a dismissal left an exit")
            return
        }
    }

    @Test("a second dismissal of a closed shelf does nothing, so it cannot run the hide handler again")
    func whenAlreadyClosed_thenADismissalIsIgnored() {
        let (state, counter) = state()
        state.close()

        state.close()
        state.close(.dismissed)

        #expect(counter.hides == 1)
    }

    @Test("an exit is taken once: the next close starts from a dismissal")
    func whenTaken_thenCleared() {
        let (state, _) = state()
        var ran = false
        state.close(.afterHide { ran = true })

        guard case let .afterHide(action) = state.takePendingExit() else {
            Issue.record("the action was lost")
            return
        }
        action()
        #expect(ran)
        guard case .dismissed = state.takePendingExit() else {
            Issue.record("the exit was not cleared")
            return
        }
    }

    @Test("a dismissal after a chosen clip replaces it: Escape right after a click does not paste")
    func whenDismissedAfterAChoice_thenTheChoiceIsDropped() {
        let (state, _) = state()
        state.close(.afterHide {})
        state.isOverlayVisible = true

        state.close()

        guard case .dismissed = state.takePendingExit() else {
            Issue.record("the earlier exit survived the dismissal")
            return
        }
    }

    @Test("what the hide handler does follows the exit")
    func plan_followsTheExit() {
        #expect(ShelfExit.dismissed.plan == .nothing)
        #expect(ShelfExit.startStack.plan == .startStack)
        #expect(ShelfExit.afterHide {}.plan == .runAfterHide)
        #expect(!ShelfExit.dismissed.actsWhenAlreadyClosed)
        #expect(ShelfExit.startStack.actsWhenAlreadyClosed)
    }
}
