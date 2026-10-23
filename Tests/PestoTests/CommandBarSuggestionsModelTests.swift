// SPDX-License-Identifier: MIT
import PestoCore
import Testing
@testable import Pesto

@MainActor
@Suite("When the command bar asks for its suggestions")
struct CommandBarSuggestionsModelTests {
    private final class Calls: @unchecked Sendable {
        var loads = 0
    }

    private static let sample = CommandBarSuggestions(
        topTags: ["work"], topApps: [SourceApp(bundleID: "com.apple.Notes", name: "Notes")]
    )

    private func appState(visible: Bool = true, locked: Bool = false, calls: Calls) -> AppState {
        let state = AppState()
        state.isOverlayVisible = visible
        state.isHistoryLocked = locked
        state.commandBarSuggestions = {
            calls.loads += 1
            return Self.sample
        }
        return state
    }

    @Test("a shelf on screen shows what the storage actor reports")
    func whenShelfIsVisible_thenSuggestionsAreLoaded() async {
        let calls = Calls()
        let model = CommandBarSuggestionsModel(debounce: .milliseconds(1), observesSaves: false)

        let state = appState(calls: calls)

        model.start(state)
        await model.settle()

        #expect(model.suggestions == Self.sample)
        model.stop()
        withExtendedLifetime(state) {}
    }

    @Test("the app in front is read again at every open, so the chips follow the app being pasted into")
    func whenTheShelfOpensAgain_thenTheFrontmostAppIsReread() async {
        let calls = Calls()
        let model = CommandBarSuggestionsModel(debounce: .milliseconds(1), observesSaves: false)
        let state = appState(calls: calls)
        state.frontmostAppBundleID = "com.apple.Notes"
        state.frontmostAppName = "Notes"
        model.start(state)
        await model.settle()
        #expect(model.frontmost == SourceApp(bundleID: "com.apple.Notes", name: "Notes"))

        state.frontmostAppBundleID = "com.apple.Safari"
        state.frontmostAppName = "Safari"
        model.refresh()
        await model.settle()

        #expect(model.frontmost == SourceApp(bundleID: "com.apple.Safari", name: "Safari"))
        model.stop()
    }

    @Test("a hidden shelf does no work")
    func whenShelfIsHidden_thenNothingIsLoaded() async {
        let calls = Calls()
        let model = CommandBarSuggestionsModel(debounce: .milliseconds(1), observesSaves: false)

        let state = appState(visible: false, calls: calls)

        model.start(state)
        await model.settle()

        #expect(calls.loads == 0)
        #expect(model.suggestions == .empty)
        model.stop()
        withExtendedLifetime(state) {}
    }

    @Test("the pinned window counts as on screen")
    func whenPinnedWindowIsVisible_thenSuggestionsAreLoaded() async {
        let calls = Calls()
        let state = appState(visible: false, calls: calls)
        state.isPinnedWindowVisible = true
        let model = CommandBarSuggestionsModel(debounce: .milliseconds(1), observesSaves: false)

        model.start(state)
        await model.settle()

        #expect(model.suggestions == Self.sample)
        model.stop()
        withExtendedLifetime(state) {}
    }

    @Test("a locked history shows no tags and asks for none")
    func whenHistoryIsLocked_thenNothingIsShownOrLoaded() async {
        let calls = Calls()
        let state = appState(calls: calls)
        let model = CommandBarSuggestionsModel(debounce: .milliseconds(1), observesSaves: false)
        model.start(state)
        await model.settle()
        #expect(model.suggestions == Self.sample)

        state.isHistoryLocked = true
        model.refresh()
        await model.settle()

        #expect(model.suggestions == .empty)
        model.stop()
        withExtendedLifetime(state) {}
    }

    @Test("a burst of refresh requests loads once")
    func whenManyRefreshesArrive_thenOneLoadRuns() async {
        let calls = Calls()
        let model = CommandBarSuggestionsModel(debounce: .milliseconds(30), observesSaves: false)
        let state = appState(calls: calls)
        model.start(state)
        await model.settle()
        let before = calls.loads

        for _ in 0..<10 {
            model.refresh(afterDelay: true)
        }
        await model.settle()

        #expect(calls.loads == before + 1)
        model.stop()
        withExtendedLifetime(state) {}
    }
}
