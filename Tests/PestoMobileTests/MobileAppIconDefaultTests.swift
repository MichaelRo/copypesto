// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

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

    @Test("icon resolution follows light and dark themes independently")
    func whenDarkThemeDiffers_thenResolvedThemeFollowsAppearance() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(AppTheme.parmesan.rawValue, for: Setting.appTheme)
        defaults.set(AppTheme.mortar.rawValue, for: Setting.appThemeDark)

        #expect(MobileAppIcon.resolvedTheme(defaults: defaults, isDark: false) == .parmesan)
        #expect(MobileAppIcon.resolvedTheme(defaults: defaults, isDark: true) == .mortar)

        defaults.set("", for: Setting.appThemeDark)
        #expect(MobileAppIcon.resolvedTheme(defaults: defaults, isDark: true) == .parmesan)
    }
}
