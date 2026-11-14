// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The theme's ground and accent on iPhone and iPad")
struct MobileThemeTests {
    @Test("the ground is the theme's own, in each appearance", arguments: AppTheme.allCases)
    func whenAThemeIsChosen_thenItsGroundIsUsed(theme: AppTheme) {
        for dark in [false, true] {
            let resolved = MobileTheme.resolve(accent: "brand", theme: theme.rawValue, darkTheme: "", isDark: dark)
            #expect(resolved.groundHex == theme.groundHex(dark: dark))
            #expect(resolved.accentHex == theme.accentHex(dark: dark))
        }
    }

    @Test("a dark-mode theme applies only in dark")
    func whenADarkThemeIsSet_thenDarkUsesIt() {
        let light = MobileTheme.resolve(accent: "brand", theme: "basil", darkTheme: "mortar", isDark: false)
        let dark = MobileTheme.resolve(accent: "brand", theme: "basil", darkTheme: "mortar", isDark: true)
        #expect(light.groundHex == AppTheme.basil.groundHex(dark: false))
        #expect(dark.groundHex == AppTheme.mortar.groundHex(dark: true))
    }

    @Test("a preset or a chosen color is moved until it reads as text on the ground")
    func whenAnAccentIsChosen_thenItReads() {
        for stored in AccentPreset.allCases.map(\.rawValue) + ["FFFF00", "111111"] {
            for theme in AppTheme.allCases {
                for dark in [false, true] {
                    let resolved = MobileTheme.resolve(
                        accent: stored, theme: theme.rawValue, darkTheme: "", isDark: dark
                    )
                    #expect(ContrastRatio.between(resolved.accentHex, resolved.groundHex) >= 4.5)
                }
            }
        }
    }

    @Test("light and dark force the appearance; System and anything unknown leave it to iOS")
    func whenAppearanceIsChosen_thenTheSchemeFollows() {
        #expect(MobileTheme.colorScheme(appearance: "light") == .light)
        #expect(MobileTheme.colorScheme(appearance: "dark") == .dark)
        #expect(MobileTheme.colorScheme(appearance: "system") == nil)
        #expect(MobileTheme.colorScheme(appearance: "sepia") == nil)
    }
}
