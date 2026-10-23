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
}
