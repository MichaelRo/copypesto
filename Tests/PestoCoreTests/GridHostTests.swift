// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("GridHost")
struct GridHostTests {
    @Test("a grid with neither paste flag is the shelf")
    func whenNeitherFlag_thenShelf() {
        #expect(GridHost(copyOnly: false, pasteImmediately: false) == .shelf)
    }

    @Test(
        "the pinned window is the host whether a tap copies or pastes",
        arguments: [(true, false), (false, true), (true, true)]
    )
    func whenEitherFlag_thenPinnedWindow(copyOnly: Bool, pasteImmediately: Bool) {
        #expect(GridHost(copyOnly: copyOnly, pasteImmediately: pasteImmediately) == .pinnedWindow)
    }
}
