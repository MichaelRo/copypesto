// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("The menu bar icon's place")
struct MenuBarIconPlaceTests {
    private let screens = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),
        CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    ]

    @Test("an icon inside a screen is on screen")
    func whenFrameIsInAScreen_thenOnScreen() {
        #expect(MenuBarIconPlace.isOnScreen(frame: CGRect(x: 1300, y: 960, width: 24, height: 22), screens: screens))
        #expect(MenuBarIconPlace.isOnScreen(frame: CGRect(x: 2000, y: 1058, width: 24, height: 22), screens: screens))
    }

    @Test("a crowded bar puts the icon left of the screen or beyond it")
    func whenFrameIsOutsideEveryScreen_thenNotOnScreen() {
        #expect(!MenuBarIconPlace.isOnScreen(frame: CGRect(x: -64, y: 960, width: 24, height: 22), screens: screens))
        #expect(!MenuBarIconPlace.isOnScreen(frame: CGRect(x: 3600, y: 960, width: 24, height: 22), screens: screens))
    }

    @Test("no window, an empty frame or no screen is not on screen")
    func whenThereIsNothingToSee_thenNotOnScreen() {
        #expect(!MenuBarIconPlace.isOnScreen(frame: nil, screens: screens))
        #expect(!MenuBarIconPlace.isOnScreen(frame: .zero, screens: screens))
        #expect(!MenuBarIconPlace.isOnScreen(frame: CGRect(x: 10, y: 10, width: 24, height: 22), screens: []))
    }
}
