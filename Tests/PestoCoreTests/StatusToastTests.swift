// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The status toast")
struct StatusToastTests {
    @Test("a manual-paste toast keeps its click and its time, and sits above the Dock")
    func whenManualPaste_thenItKeepsItsBehavior() {
        let plain = StatusToast.manualPaste(.pressCommandV)
        let explained = StatusToast.manualPaste(.autoPasteIsOff)

        #expect(!plain.isClickable)
        #expect(explained.isClickable)
        #expect(plain.visibleSeconds == ManualPasteToast.pressCommandV.visibleSeconds)
        #expect(explained.visibleSeconds == ManualPasteToast.autoPasteIsOff.visibleSeconds)
        #expect(plain.placement == .aboveDock)
    }

    @Test("the update notice sits under the menu bar where the click happened, and stays long enough to read")
    func whenUpdatesUnavailable_thenItAppearsNearTheMenuBar() {
        let toast = StatusToast.updatesUnavailable

        #expect(toast.placement == .belowMenuBar)
        #expect(!toast.isClickable)
        #expect(toast.visibleSeconds >= 4)
    }

    @Test("the up-to-date notice sits under the menu bar like the update notice, with no click and a readable time")
    func whenUpToDate_thenItAppearsNearTheMenuBarAndStaysReadable() {
        let toast = StatusToast.upToDate

        #expect(toast.placement == .belowMenuBar)
        #expect(!toast.isClickable)
        #expect(toast.visibleSeconds == 4)
    }

    @Test("the notice that a paste found its files gone sits above the Dock and stays long enough to read")
    func whenFilesGone_thenItIsReadable() {
        let toast = StatusToast.filesGone

        #expect(toast.placement == .aboveDock)
        #expect(!toast.isClickable)
        #expect(toast.visibleSeconds >= 4)
    }
}
