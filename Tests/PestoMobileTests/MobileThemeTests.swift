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

    @Test("Color.toHex and AccentChoice round-trip custom accent hex strings")
    func whenCustomAccentHexChosen_thenChoiceAndThemeResolve() throws {
        let hex = try #require(Color(hex: "FF5733")?.toHex())
        let stored = AccentChoice.custom(hex).stored
        #expect(AccentChoice(stored: stored) == .custom("FF5733"))

        let light = MobileTheme.resolve(accent: stored, theme: "basil", darkTheme: "", isDark: false)
        let dark = MobileTheme.resolve(accent: stored, theme: "basil", darkTheme: "", isDark: true)
        #expect(ContrastRatio.between(light.accentHex, light.groundHex) >= 4.5)
        #expect(ContrastRatio.between(dark.accentHex, dark.groundHex) >= 4.5)
    }

    @Test("applying an accent tint sets tintColor on every window of the app")
    @MainActor
    func whenAccentTintApplied_thenEveryWindowCarriesIt() throws {
        let scenes = UIApplication.shared.connectedScenes
        let windows = scenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        try #require(!windows.isEmpty, "the hosted test runs inside the app's window")
        let before = windows.map(\.tintColor)
        defer { zip(windows, before).forEach { $0.tintColor = $1 } }

        MobileAppearance.applyTint(.systemPurple, to: scenes)
        #expect(windows.allSatisfy { $0.tintColor == .systemPurple })
    }

    @Test("dark mode falls back to the light theme when no separate dark theme is stored")
    func whenDarkThemeUnset_thenActiveThemeFallsBackToLightTheme() {
        #expect(AppTheme.resolve(light: "basil", dark: "", isDark: true) == .basil)
        #expect(AppTheme.resolve(light: "basil", dark: "mortar", isDark: true) == .mortar)
    }

    @Test("leading-edge pull opens settings only for horizontal pulls from the leading edge")
    func whenLeadingEdgeSwiped_thenSettingsEdgeSwipeDecisionMatches() {
        #expect(SettingsEdgeSwipe.isLeadingEdgeStart(12, width: 393, isRTL: false))
        #expect(!SettingsEdgeSwipe.isLeadingEdgeStart(140, width: 393, isRTL: false))
        #expect(SettingsEdgeSwipe.isLeadingEdgeStart(380, width: 393, isRTL: true))
        #expect(!SettingsEdgeSwipe.isLeadingEdgeStart(12, width: 393, isRTL: true))
        #expect(!SettingsEdgeSwipe.isLeadingEdgeStart(12, width: 0, isRTL: false))

        #expect(SettingsEdgeSwipe.shouldOpen(
            startX: 12, translation: CGSize(width: 72, height: 6), width: 393, isRTL: false
        ))
        #expect(!SettingsEdgeSwipe.shouldOpen(
            startX: 140, translation: CGSize(width: 72, height: 0), width: 393, isRTL: false
        ))
        #expect(!SettingsEdgeSwipe.shouldOpen(
            startX: 12, translation: CGSize(width: 40, height: 0), width: 393, isRTL: false
        ))
        #expect(!SettingsEdgeSwipe.shouldOpen(
            startX: 12, translation: CGSize(width: 60, height: 90), width: 393, isRTL: false
        ))
        #expect(SettingsEdgeSwipe.shouldOpen(
            startX: 380, translation: CGSize(width: -72, height: 4), width: 393, isRTL: true
        ))
        #expect(!SettingsEdgeSwipe.shouldOpen(
            startX: 12, translation: CGSize(width: 72, height: 0), width: 393, isRTL: true
        ))

        #expect(SettingsEdgeSwipe.shouldClose(translation: CGSize(width: -72, height: 6), isRTL: false))
        #expect(!SettingsEdgeSwipe.shouldClose(translation: CGSize(width: 72, height: 0), isRTL: false))
        #expect(!SettingsEdgeSwipe.shouldClose(translation: CGSize(width: -60, height: 80), isRTL: false))
        #expect(SettingsEdgeSwipe.shouldClose(translation: CGSize(width: 72, height: 6), isRTL: true))
        #expect(!SettingsEdgeSwipe.shouldClose(translation: CGSize(width: -72, height: 0), isRTL: true))
    }
}
