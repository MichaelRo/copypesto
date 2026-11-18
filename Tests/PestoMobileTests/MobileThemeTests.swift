// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
import UIKit
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

    @Test("light and dark force the windows' style; System and anything unknown hand it back to iOS")
    func whenAppearanceIsChosen_thenTheWindowStyleFollows() {
        #expect(MobileAppearance.interfaceStyle(appearance: "light") == .light)
        #expect(MobileAppearance.interfaceStyle(appearance: "dark") == .dark)
        #expect(MobileAppearance.interfaceStyle(appearance: "system") == .unspecified)
        #expect(MobileAppearance.interfaceStyle(appearance: "sepia") == .unspecified)
    }

    @Test("applying the style sets every window of the app, and System clears it again")
    @MainActor
    func whenStyleApplied_thenEveryWindowCarriesIt() throws {
        let scenes = UIApplication.shared.connectedScenes
        let windows = scenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        try #require(!windows.isEmpty, "the hosted test runs inside the app's window")
        let before = windows.map(\.overrideUserInterfaceStyle)
        defer { zip(windows, before).forEach { $0.overrideUserInterfaceStyle = $1 } }

        MobileAppearance.apply(.dark, to: scenes)
        #expect(windows.allSatisfy { $0.overrideUserInterfaceStyle == .dark })
        MobileAppearance.apply(.unspecified, to: scenes)
        #expect(windows.allSatisfy { $0.overrideUserInterfaceStyle == .unspecified })
    }
}
