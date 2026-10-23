// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Where the shelf may open as a small menu")
struct ShelfOpenSourceTests {
    @Test("only the shortcut may open the small menu at the cursor")
    func whenAnyRoute_thenOnlyTheHotkeyAllowsTheQuickMenu() {
        #expect(ShelfOpenSource.allCases.filter(\.allowsQuickMenu) == [.hotkey])
    }

    @Test("the menu bar item, links, scripts and Shortcuts always open the shelf they name")
    func whenNotTheHotkey_thenTheFullShelf() {
        for source in [ShelfOpenSource.statusMenu, .link, .script, .intent, .internalRoute] {
            #expect(!source.allowsQuickMenu, "\(source)")
        }
    }
}
