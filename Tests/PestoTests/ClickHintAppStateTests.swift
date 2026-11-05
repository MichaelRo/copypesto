// SPDX-License-Identifier: MIT
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
