// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import Testing
@testable import PestoCore

@Suite("Where the shelf sits")
struct ShelfPositionTests {
    /// A notched laptop: the menu bar is 38 pt tall and shows; the Dock is 70 pt at the bottom.
    private let laptop = ShelfPosition.Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 874),
        safeAreaTop: 38
    )

    @Test("the bottom shelf is as wide as the usable screen and rests on the Dock")
    func whenBottom_thenFlushWithTheDock() {
        let frame = ShelfPosition.bottom.frame(on: laptop, height: 250)
        #expect(frame == CGRect(x: 0, y: 70, width: 1512, height: 250))
    }

    @Test("under the notch the shelf hangs from the bottom of the menu bar")
    func whenUnderNotch_thenBelowTheMenuBar() {
        let frame = ShelfPosition.underNotch.frame(on: laptop, height: 250)
        #expect(frame == CGRect(x: 0, y: 694, width: 1512, height: 250))
        #expect(frame.maxY == laptop.visibleFrame.maxY)
    }

    @Test("with the menu bar hidden the shelf still stays below the notch")
    func whenMenuBarHidesItself_thenStillBelowTheNotch() {
        let hidden = ShelfPosition.Screen(
            frame: laptop.frame,
            visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 912),
            safeAreaTop: 38
        )
        let frame = ShelfPosition.underNotch.frame(on: hidden, height: 250)
        #expect(frame.maxY == 944)
    }

    @Test("a screen with no notch has no safe area and the shelf hangs from the menu bar")
    func whenNoNotch_thenFromTheMenuBar() {
        let external = ShelfPosition.Screen(
            frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
            safeAreaTop: 0
        )
        let frame = ShelfPosition.underNotch.frame(on: external, height: 300)
        #expect(frame == CGRect(x: 1512, y: 1115, width: 2560, height: 300))
    }

    @Test("a shelf taller than the screen is cut to it, never above or below it")
    func whenTooTall_thenCut() {
        let frame = ShelfPosition.underNotch.frame(on: laptop, height: 2000)
        #expect(frame.height == laptop.visibleFrame.height)
        #expect(frame.minY == laptop.visibleFrame.minY)
    }

    @Test("the shelf slides in from the edge it hangs on, and the hover card opens away from it")
    func whenSliding_thenFromItsOwnEdge() {
        #expect(ShelfPosition.bottom.slideOffset(height: 250) == -250)
        #expect(ShelfPosition.underNotch.slideOffset(height: 250) == 250)
        #expect(ShelfPosition.bottom.hoverCardOpensAbove)
        #expect(!ShelfPosition.underNotch.hoverCardOpensAbove)
    }

    @Test("the shelf that hangs from the menu bar is called Top, and keeps the value earlier builds stored")
    func whenTitled_thenTopWithTheOldStoredValue() {
        #expect(ShelfPosition.bottom.title == "Bottom")
        #expect(ShelfPosition.underNotch.title == "Top")
        #expect(ShelfPosition.underNotch.rawValue == "underNotch")
        #expect(ShelfPosition.allCases.map(\.title) == ["Bottom", "Top"])
    }

    @Test("the hover card opens away from the shelf, and always above the pinned window")
    func whenHoverCardSide_thenAwayFromTheHost() {
        #expect(ShelfPosition.hoverCardOpensAbove(hostIsShelf: true, position: .bottom))
        #expect(!ShelfPosition.hoverCardOpensAbove(hostIsShelf: true, position: .underNotch))
        #expect(ShelfPosition.hoverCardOpensAbove(hostIsShelf: false, position: .bottom))
        #expect(ShelfPosition.hoverCardOpensAbove(hostIsShelf: false, position: .underNotch))
    }

    @Test("a stored value that is not a position is the bottom, and the setting is registered")
    func whenStoredValueIsUnknown_thenBottom() {
        #expect(ShelfPosition(stored: "") == .bottom)
        #expect(ShelfPosition(stored: "sideways") == .bottom)
        #expect(ShelfPosition(stored: "underNotch") == .underNotch)
        #expect(Setting.shelfPosition.defaultValue == ShelfPosition.bottom.rawValue)
        #expect(Setting.allNames.contains(Setting.shelfPosition.name))
        #expect(SettingsIndex.entries.contains { $0.title == "Shelf position" })
    }
}
