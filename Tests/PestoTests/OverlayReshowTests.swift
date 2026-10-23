// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto

@Suite("OverlayWindowController — re-show during hide")
@MainActor
struct OverlayReshowTests {
    private func settle(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    @Test("showing again while the hide animation runs leaves the overlay visible")
    func whenShownDuringHide_thenStillVisibleAfterHideWouldHaveFinished() async {
        let controller = OverlayWindowController(appState: AppState())
        controller.show()
        await settle(0.4)

        controller.hide()
        await settle(0.05)
        controller.show()
        await settle(0.6)

        #expect(controller.overlayWindow.isVisible)
        controller.hide()
        await settle(0.5)
    }

    @Test("a hide with a completion still runs the completion when the overlay was re-shown")
    func whenReshownDuringHideWithCompletion_thenCompletionStillRuns() async {
        let controller = OverlayWindowController(appState: AppState())
        controller.show()
        await settle(0.4)
        var completed = false

        controller.hide { completed = true }
        await settle(0.05)
        controller.show()
        await settle(0.6)

        #expect(completed)
        controller.hide()
        await settle(0.5)
    }
}
