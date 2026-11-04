// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Where the Settings window reopens")
struct SettingsWindowFrameTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 944)

    @Test("a frame saved by an older, taller window comes back at the capped height, keeping its top edge")
    func whenTooTall_thenCapped() throws {
        let saved = CGRect(x: 417, y: 41, width: 840, height: 892)
        let frame = try #require(SettingsWindowFrame.restored(saved: saved, displays: [display]))
        #expect(frame.height == SettingsWindowFrame.maximumHeight)
        #expect(frame.maxY == saved.maxY)
        #expect(frame.width == 840)
    }

    @Test("a frame that is small, empty or off every display is dropped")
    func whenUnusable_thenNil() {
        #expect(SettingsWindowFrame
            .restored(saved: CGRect(x: 0, y: 0, width: 640, height: 440), displays: [display]) == nil)
        #expect(SettingsWindowFrame.restored(saved: .zero, displays: [display]) == nil)
        #expect(SettingsWindowFrame.restored(
            saved: CGRect(x: 5000, y: 0, width: 800, height: 700), displays: [display]
        ) == nil)
    }

    @Test("on a short display the window is limited to the display, and a good size is kept as saved")
    func whenShortDisplay_thenFits() throws {
        let short = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let frame = try #require(SettingsWindowFrame.restored(
            saved: CGRect(x: 100, y: 0, width: 800, height: 740), displays: [short]
        ))
        #expect(frame.height == 680)
        #expect(frame.minY >= short.minY && frame.maxY <= short.maxY)
        let kept = try #require(SettingsWindowFrame.restored(
            saved: CGRect(x: 100, y: 100, width: 800, height: 720), displays: [display]
        ))
        #expect(kept == CGRect(x: 100, y: 100, width: 800, height: 720))
    }

    private let external = CGRect(x: 1512, y: 0, width: 2560, height: 1415)

    @Test("a frame saved on the display the person is using reopens where it was")
    func whenSavedOnTarget_thenRestoredInPlace() {
        let saved = CGRect(x: 100, y: 100, width: 800, height: 720)
        let frame = SettingsWindowFrame.placed(saved: saved, target: display, displays: [display, external])
        #expect(frame == saved)
    }

    @Test("a frame saved on another display moves to the display the person is using, keeping its size")
    func whenSavedOnOtherDisplay_thenCenteredOnTarget() {
        let saved = CGRect(x: 100, y: 100, width: 840, height: 720)
        let frame = SettingsWindowFrame.placed(saved: saved, target: external, displays: [display, external])
        #expect(frame.size == saved.size)
        #expect(frame.midX == external.midX)
        #expect(frame.midY == external.midY)
    }

    @Test("with no usable saved frame the default size is centered on the display the person is using")
    func whenNothingSaved_thenDefaultCenteredOnTarget() {
        for saved in [CGRect?.none, .some(.zero), .some(CGRect(x: 9000, y: 0, width: 800, height: 700))] {
            let frame = SettingsWindowFrame.placed(saved: saved, target: external, displays: [display, external])
            #expect(frame.size == SettingsWindowFrame.defaultSize)
            #expect(frame.midX == external.midX)
            #expect(frame.midY == external.midY)
        }
    }

    @Test("a frame moved to a short display is cut to fit it")
    func whenMovedToShortDisplay_thenFits() {
        let short = CGRect(x: 1512, y: 0, width: 1280, height: 720)
        let saved = CGRect(x: 100, y: 100, width: 800, height: 740)
        let frame = SettingsWindowFrame.placed(saved: saved, target: short, displays: [display, short])
        #expect(frame.height == 680)
        #expect(short.contains(frame))
    }
}
