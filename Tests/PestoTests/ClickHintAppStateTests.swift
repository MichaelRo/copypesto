// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("The click hint on the shelf", .serialized)
    @MainActor
    struct ClickHintAppStateTests {
        private func reset() {
            AppDefaults.store.removeObject(forKey: Setting.doubleClickPasted.name)
            AppDefaults.store.removeObject(forKey: Setting.clickHintShownCount.name)
        }

        @Test("a double-click paste is remembered, so the hint never shows again")
        func whenDoubleClickPastes_thenRemembered() {
            defer { reset() }
            reset()
            let state = AppState()

            state.noteShelfClick(.double, tap: .paste)

            #expect(AppDefaults.store.value(for: Setting.doubleClickPasted))
        }

        @Test("a paste or a double-click takes the hint away at once")
        func whenPasteOrDouble_thenHintGoes() {
            defer { reset() }
            reset()
            let state = AppState()
            state.isClickHintVisible = true

            state.noteShelfClick(.double, tap: .ignore)

            #expect(!state.isClickHintVisible)
        }

        @Test("a showing counts once, when it is drawn, and a second click while it is up neither counts nor restarts")
        func whenShown_thenCountedOnceWhenDrawn() async throws {
            defer { reset() }
            reset()
            let state = AppState()
            state.isOverlayVisible = true
            defer { state.isOverlayVisible = false }

            state.noteShelfClick(.single, tap: .focus)
            #expect(AppDefaults.store.value(for: Setting.clickHintShownCount) == 0)
            try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.4))
            #expect(state.isClickHintVisible)
            #expect(AppDefaults.store.value(for: Setting.clickHintShownCount) == 0)

            state.noteClickHintDrawn()
            let task = state.clickHintTask
            state.noteShelfClick(.single, tap: .focus)

            #expect(AppDefaults.store.value(for: Setting.clickHintShownCount) == 1)
            #expect(state.clickHintTask == task)
            state.hideClickHint()
        }

        @Test("the No results button is the last stop Tab reaches, and Return on it clears the filters")
        func whenNoResultsAdvice_thenTabReachesItAndReturnClears() throws {
            let state = AppState()
            state.searchTypeFilter = ["image"]
            state.noResultsAdvice = NoResultsAdvice.make(query: "x", kinds: [.image])
            let chip = FilterChipAction(spokenName: "Image", isActive: { false }, toggle: {})
            state.filterChipActions = try [chip, #require(state.noResultsChipAction())]

            #expect(!state.isKeyboardOnNoResultsAdvice)
            state.moveFilterChipCursor(by: -1)
            #expect(state.filterChipCursor == 1)
            #expect(state.isKeyboardOnNoResultsAdvice)

            #expect(state.toggleFilterChipAtCursor())
            #expect(state.searchTypeFilter.isEmpty)
        }

        @Test("with no advice there is no extra stop")
        func whenNoAdvice_thenNoExtraAction() {
            let state = AppState()
            #expect(state.noResultsChipAction() == nil)
            #expect(!state.isKeyboardOnNoResultsAdvice)
        }

        @Test("Clear Search empties the field and keeps the filters")
        func whenClearSearch_thenTextGoes() {
            let state = AppState()
            state.searchText = "abc"
            state.searchTypeFilter = ["image"]

            state.clearForNoResults(.clearSearch)

            #expect(state.searchText.isEmpty)
            #expect(state.searchTypeFilter == ["image"])
        }

        @Test("a single click that selects shows no hint and counts nothing")
        func whenClickSelects_thenNoHint() {
            defer { reset() }
            reset()
            let state = AppState()

            state.noteShelfClick(.single, tap: .toggleSelection)

            #expect(!state.isClickHintVisible)
            #expect(AppDefaults.store.value(for: Setting.clickHintShownCount) == 0)
        }
    }
}
