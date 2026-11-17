// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Multi-display and Dock-edge placement math")
struct MultiDisplayPlacementTests {
    private let laptopNotched = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let laptopVisible = CGRect(x: 0, y: 70, width: 1512, height: 874)
    private let externalRight = CGRect(x: 1512, y: -220, width: 2560, height: 1440)
    private let externalRightVisible = CGRect(x: 1512, y: -220, width: 2560, height: 1415)
    private let externalLeftDockLeft = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    private let externalLeftDockLeftVisible = CGRect(x: -1840, y: 0, width: 1840, height: 1055)

    @Test("FloatingWindowPlacement translates saved frame across displays with differing origins and heights")
    func whenMovingAcrossDisplays_thenPreservesRelativeCornerAndFits() {
        let savedOnLaptop = CGRect(x: 100, y: 120, width: 420, height: 540)
        let displays = [laptopVisible, externalRightVisible, externalLeftDockLeftVisible]

        let movedRight = FloatingWindowPlacement.frame(
            saved: savedOnLaptop, displays: displays, target: externalRightVisible
        )
        #expect(movedRight.origin.x == externalRightVisible.minX + 100)
        #expect(movedRight.origin.y == externalRightVisible.minY + (120 - 70))
        #expect(movedRight.size == savedOnLaptop.size)

        let hugeSaved = CGRect(x: 1600, y: 0, width: 2200, height: 1200)
        let fittedOnLaptop = FloatingWindowPlacement.frame(
            saved: hugeSaved, displays: displays, target: laptopVisible
        )
        #expect(laptopVisible.contains(fittedOnLaptop))
        #expect(fittedOnLaptop.width == laptopVisible.width)
        #expect(fittedOnLaptop.height == laptopVisible.height)
    }

    @Test("QuickMenuMetrics.frame stays inside secondary display and avoids left/right Dock")
    func whenQuickMenuNearEdgesOnSecondaryDisplay_thenClampedToVisibleFrame() {
        let panelSize = QuickMenuMetrics.panelSize(
            cardSize: CGSize(width: 180, height: 120),
            cards: 4,
            maxWidth: externalLeftDockLeftVisible.width - 16
        )

        let nearDockLeft = CGRect(x: -1835, y: 500, width: 2, height: 18)
        let frameLeft = QuickMenuMetrics.frame(
            near: nearDockLeft, panelSize: panelSize, in: externalLeftDockLeftVisible
        )
        #expect(frameLeft.minX == externalLeftDockLeftVisible.minX + 8)
        #expect(externalLeftDockLeftVisible.contains(frameLeft))

        let nearTopRight = CGRect(
            x: externalRightVisible.maxX - 10,
            y: externalRightVisible.maxY - 12,
            width: 2,
            height: 18
        )
        let frameTopRight = QuickMenuMetrics.frame(
            near: nearTopRight, panelSize: panelSize, in: externalRightVisible
        )
        #expect(frameTopRight.maxX == externalRightVisible.maxX - 8)
        #expect(frameTopRight.maxY <= nearTopRight.minY - 8)
        #expect(externalRightVisible.contains(frameTopRight))
    }

    @Test("StackHUD origin respects right Dock and secondary display bounds")
    func whenStackHUDOnSecondaryOrRightDock_thenInsetFromVisibleMaxCorner() {
        let hudSize = CGSize(width: 260, height: 64)
        let rightDockVisible = CGRect(x: 0, y: 0, width: 1432, height: 944)
        let originRightDock = FloatingWindowPlacement.stackHUDOrigin(panelSize: hudSize, in: rightDockVisible)
        #expect(originRightDock == CGPoint(x: 1432 - 260 - 16, y: 944 - 64 - 8))

        let originExternal = FloatingWindowPlacement.stackHUDOrigin(panelSize: hudSize, in: externalRightVisible)
        #expect(
            originExternal == CGPoint(
                x: externalRightVisible.maxX - 260 - 16,
                y: externalRightVisible.maxY - 64 - 8
            )
        )
    }

    @Test("ShelfPosition underNotch respects safeAreaTop when menu bar is hidden on notched display")
    func whenNotchAndHiddenMenuBar_thenShelfStartsBelowSafeAreaTop() {
        let screen = ShelfPosition.Screen(
            frame: laptopNotched,
            visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 912),
            safeAreaTop: 38
        )
        let frame = ShelfPosition.underNotch.frame(on: screen, height: 220)
        #expect(frame.maxY == laptopNotched.maxY - 38)
    }
}
