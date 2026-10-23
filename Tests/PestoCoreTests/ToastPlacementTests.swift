// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("ToastPlacement")
struct ToastPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let size = CGSize(width: 360, height: 44)

    @Test("an update notice sits under the menu bar icon, centred on it, 8 pt below the bar")
    func whenIconIsKnown_thenCentredUnderIt() {
        let icon = CGRect(x: 1100, y: 944, width: 30, height: 24)

        let origin = ToastPlacement.origin(
            for: .belowMenuBar, size: size, visibleFrame: visible, screenFrame: screen, anchor: icon
        )

        #expect(origin.x == CGFloat(1115 - 180))
        #expect(origin.y == CGFloat(944 - 8 - 44))
    }

    @Test("near a screen edge the notice slides in until it fits, 12 pt from the edge")
    func whenIconIsNearTheEdge_thenClamped() {
        let right = CGRect(x: 1480, y: 944, width: 30, height: 24)
        let left = CGRect(x: 4, y: 944, width: 30, height: 24)

        let rightOrigin = ToastPlacement.origin(
            for: .belowMenuBar, size: size, visibleFrame: visible, screenFrame: screen, anchor: right
        )
        let leftOrigin = ToastPlacement.origin(
            for: .belowMenuBar, size: size, visibleFrame: visible, screenFrame: screen, anchor: left
        )

        #expect(rightOrigin.x == CGFloat(1512 - 360 - 12))
        #expect(leftOrigin.x == 12)
    }

    @Test("with no menu bar icon the notice is centred under the menu bar")
    func whenNoIcon_thenCentred() {
        let origin = ToastPlacement.origin(
            for: .belowMenuBar, size: size, visibleFrame: visible, screenFrame: screen, anchor: nil
        )

        #expect(origin.x == CGFloat(756 - 180))
        #expect(origin.y == CGFloat(944 - 44 - 16))
    }

    @Test("an icon on another display, or one the system has hidden, is not used")
    func whenIconIsNotOnThisScreen_thenCentred() {
        let elsewhere = CGRect(x: 2000, y: 944, width: 30, height: 24)
        let hidden = CGRect(x: 1100, y: 944, width: 0, height: 0)

        for anchor in [elsewhere, hidden] {
            let origin = ToastPlacement.origin(
                for: .belowMenuBar, size: size, visibleFrame: visible, screenFrame: screen, anchor: anchor
            )
            #expect(origin.x == CGFloat(756 - 180))
        }
    }

    @Test("a paste notice still sits 80 pt above the bottom, centred")
    func whenAboveDock_thenAsBefore() {
        let origin = ToastPlacement.origin(
            for: .aboveDock, size: size, visibleFrame: visible, screenFrame: screen, anchor: nil
        )

        #expect(origin.x == CGFloat(756 - 180))
        #expect(origin.y == 80)
    }
}
