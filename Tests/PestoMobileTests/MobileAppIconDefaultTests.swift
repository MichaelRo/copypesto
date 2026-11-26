// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("On iPhone and iPad the icon follows the theme only once the person turns it on")
struct MobileAppIconDefaultTests {
    @Test("Match App Icon starts off, so closing Settings never brings iOS's icon alert unasked")
    func whenNothingIsStored_thenMatchingIsOff() {
        #expect(Setting.matchesAppIcon.defaultValue == false)
        #expect(ThrowawayDefaults.make().value(for: Setting.matchesAppIcon) == false)
    }

    @Test("a choice the person made is kept")
    func whenTheSwitchWasTurnedOn_thenItStaysOn() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(true, for: Setting.matchesAppIcon)
        #expect(defaults.value(for: Setting.matchesAppIcon) == true)
    }
}
