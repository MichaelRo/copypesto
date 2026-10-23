// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The manual-paste toast")
struct ManualPasteToastTests {
    @Test("without Accessibility the first toast of a launch says auto-paste is off and can be clicked")
    func whenNotTrustedFirstTime_thenItExplains() {
        let toast = ManualPasteToast.choose(
            accessibilityTrusted: false,
            declinedAutoPaste: false,
            alreadyExplained: false
        )

        #expect(toast == .autoPasteIsOff)
        #expect(toast.isClickable)
        #expect(toast.visibleSeconds > ManualPasteToast.pressCommandV.visibleSeconds)
        #expect(toast.visibleSeconds >= 10, "a toast to click needs time to read, reach and click (WCAG 2.2.1)")
    }

    @Test("it explains once per launch, and never to someone who chose to go without auto-paste")
    func whenExplainedOrDeclined_thenTheBareLine() {
        #expect(ManualPasteToast
            .choose(accessibilityTrusted: false, declinedAutoPaste: false, alreadyExplained: true) == .pressCommandV)
        #expect(ManualPasteToast
            .choose(accessibilityTrusted: false, declinedAutoPaste: true, alreadyExplained: false) == .pressCommandV)
    }

    @Test("with Accessibility the toast is the bare line, because the keystroke failed for another reason")
    func whenTrusted_thenTheBareLine() {
        let toast = ManualPasteToast.choose(
            accessibilityTrusted: true,
            declinedAutoPaste: false,
            alreadyExplained: false
        )

        #expect(toast == .pressCommandV)
        #expect(!toast.isClickable)
    }
}
