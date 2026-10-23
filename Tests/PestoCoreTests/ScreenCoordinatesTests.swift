// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("ScreenCoordinates")
struct ScreenCoordinatesTests {
    @Test("an AX rect is flipped against the primary screen height")
    func whenAXRect_thenFlippedAgainstPrimaryHeight() {
        let ax = CGRect(x: 100, y: 200, width: 2, height: 16)

        let cocoa = ScreenCoordinates.cocoaRect(fromAX: ax, primaryScreenHeight: 900)

        #expect(cocoa == CGRect(x: 100, y: 684, width: 2, height: 16))
    }

    @Test("the flip ignores the height of any other screen")
    func whenMainScreenIsTallerThanPrimary_thenResultUsesPrimaryHeight() {
        let ax = CGRect(x: 0, y: 0, width: 2, height: 20)

        let cocoa = ScreenCoordinates.cocoaRect(fromAX: ax, primaryScreenHeight: 1080)

        #expect(cocoa.origin.y == 1060)
    }

    @Test("a rect above the primary screen (secondary display) gets a positive Cocoa y")
    func whenAXRectOnDisplayAbovePrimary_thenCocoaYExceedsPrimaryHeight() {
        let ax = CGRect(x: 0, y: -500, width: 2, height: 20)

        let cocoa = ScreenCoordinates.cocoaRect(fromAX: ax, primaryScreenHeight: 900)

        #expect(cocoa.origin.y == 1380)
    }
}
