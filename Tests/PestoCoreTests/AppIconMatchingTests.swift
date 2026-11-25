// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The app icon follows the theme unless the person chose otherwise")
struct AppIconMatchingTests {
    @Test("with matching on, a theme brings its icon; off, the icon stays")
    func whenThemeChanges_thenTheIconFollowsOnlyWhenMatching() {
        #expect(AppIconMatching.icon(for: .parmesan, matches: true, current: .basil) == .parmesan)
        #expect(AppIconMatching.icon(for: .parmesan, matches: false, current: .mortar) == .mortar)
        #expect(AppIconMatching.icon(for: .basil, matches: true, current: .pineNut) == .basil)
    }

    @Test("an install that kept an icon other than its theme's starts with matching off, once")
    func whenMigrating_thenAChosenIconIsKept() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(AppTheme.basil.rawValue, for: Setting.appTheme)
        defaults.set(AppIconChoice.mortar.rawValue, for: Setting.appIcon)
        AppIconMatching.migrate(defaults)
        #expect(defaults.value(for: Setting.matchesAppIcon) == false)
        defaults.set(true, for: Setting.matchesAppIcon)
        AppIconMatching.migrate(defaults)
        #expect(defaults.value(for: Setting.matchesAppIcon) == true, "the migration runs only while the key is unset")

        let paired = ThrowawayDefaults.make()
        paired.set(AppTheme.parmesan.rawValue, for: Setting.appTheme)
        paired.set(AppIconChoice.parmesan.rawValue, for: Setting.appIcon)
        AppIconMatching.migrate(paired)
        #expect(paired.value(for: Setting.matchesAppIcon) == true)
        #expect(Setting.allNames.contains(Setting.matchesAppIcon.name))
    }
}
