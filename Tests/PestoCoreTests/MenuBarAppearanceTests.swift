// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Menu bar appearance")
struct MenuBarAppearanceTests {
    @Test("when forcing Light or Dark does not reach the status window, nothing is pinned and the icon follows the bar")
    func whenForcingDoesNotReachTheBar_thenNoPin() {
        #expect(MenuBarAppearance.pin(underForcedApp: .light, alone: .light) == nil)
        #expect(MenuBarAppearance.pin(underForcedApp: .dark, alone: .dark) == nil)
    }

    @Test("when forcing does reach it, the icon is pinned to the bar's own appearance, not the Mac's setting")
    func whenForcingReachesTheBar_thenPinnedToTheBarsOwn() {
        #expect(MenuBarAppearance.pin(underForcedApp: .dark, alone: .light) == .light)
        #expect(MenuBarAppearance.pin(underForcedApp: .light, alone: .dark) == .dark)
    }

    @Test("the system's status bar window is not themed with the app's windows")
    func whenStatusBarWindow_thenIsSystemChrome() {
        #expect(MenuBarAppearance.isSystemChrome(windowClassName: "NSStatusBarWindow"))
        #expect(MenuBarAppearance.isSystemChrome(windowClassName: "_NSStatusBarWindow"))
        #expect(!MenuBarAppearance.isSystemChrome(windowClassName: "NSPanel"))
        #expect(!MenuBarAppearance.isSystemChrome(windowClassName: "SwiftUI.AppKitWindow"))
    }
}
