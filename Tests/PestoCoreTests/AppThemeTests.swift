// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("App themes")
struct AppThemeTests {
    /// CIE76 colour difference between two six-digit hex colours: about 2 is the least a trained eye sees, about 10
    /// is plainly another colour.
    private func colourDistance(_ first: String, _ second: String) -> Double {
        func lab(_ hex: String) -> [Double] {
            let value = UInt32(hex, radix: 16) ?? 0
            func linear(_ shift: UInt32) -> Double {
                let c = Double((value >> shift) & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let (r, g, b) = (linear(16), linear(8), linear(0))
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
            func f(_ t: Double) -> Double {
                t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116
            }
            return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))]
        }
        let (a, b) = (lab(first), lab(second))
        return zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }

    private func ground(of theme: AppTheme, dark: Bool) -> String {
        theme.groundHex(dark: dark)
    }

    @Test("an unknown or empty stored theme is Basil")
    func whenStoredValueIsUnknown_thenBasil() {
        #expect(AppTheme(stored: "") == .basil)
        #expect(AppTheme(stored: "neon") == .basil)
        #expect(AppTheme(stored: "parmesan") == .parmesan)
    }

    @Test("Basil is today's look exactly: no tint, the brand accent")
    func whenBasil_thenNoTintAndBrandAccent() {
        #expect(AppTheme.basil.tint(dark: false) == nil)
        #expect(AppTheme.basil.tint(dark: true) == nil)
        #expect(AppTheme.basil.accentHex(dark: false) == BrandPalette.accentLight)
        #expect(AppTheme.basil.accentHex(dark: true) == BrandPalette.accentDark)
    }

    @Test("a theme's accent reads as text on its own tinted ground, in light and dark")
    func whenAnyTheme_thenAccentIsReadableOnItsGround() {
        for theme in AppTheme.allCases {
            for dark in [false, true] {
                let ratio = ContrastRatio.between(theme.accentHex(dark: dark), ground(of: theme, dark: dark))
                #expect(ratio >= 4.5, "\(theme) \(dark ? "dark" : "light"): \(ratio)")
            }
        }
    }

    @Test("an accent that does not read on a theme's ground is darkened or lightened until it does, and no further")
    func whenAnyPresetOnAnyTheme_thenReadableAfterAdjusting() {
        for theme in AppTheme.allCases {
            for preset in AccentPreset.allCases {
                for dark in [false, true] {
                    let ground = theme.groundHex(dark: dark)
                    let original = preset.hex(dark: dark)
                    let adjusted = ContrastRatio.readable(original, on: ground, darkGround: dark)
                    #expect(ContrastRatio.between(adjusted, ground) >= 4.5, "\(preset) on \(theme) \(dark)")
                    if ContrastRatio.between(original, ground) >= 4.5 { #expect(adjusted == original) }
                }
            }
        }
    }

    @Test("the orange preset on Mortar's cool ground, which it did not clear, now does")
    func whenOrangeOnMortarLight_thenAdjusted() {
        let ground = AppTheme.mortar.groundHex(dark: false)
        let original = AccentPreset.orange.hex(dark: false)
        #expect(ContrastRatio.between(original, ground) < 4.5)
        let adjusted = ContrastRatio.readable(original, on: ground, darkGround: false)
        #expect(adjusted != original)
        #expect(ContrastRatio.between(adjusted, ground) >= 4.5)
    }

    @Test("primary text reads on a theme's tinted ground, in light and dark")
    func whenAnyTheme_thenPrimaryTextIsReadableOnItsGround() {
        for theme in AppTheme.allCases {
            #expect(ContrastRatio.between(BrandPalette.mortar, ground(of: theme, dark: false)) >= 7, "\(theme) light")
            #expect(ContrastRatio.between(BrandPalette.parmesan, ground(of: theme, dark: true)) >= 7, "\(theme) dark")
        }
    }

    @Test("no two themes look alike: the ground and the accent together differ plainly, in light and dark")
    func whenAnyTwoThemes_thenTheyLookDifferent() {
        for dark in [false, true] {
            for (first, second) in AppTheme.allCases.pairs() {
                let groundGap = colourDistance(ground(of: first, dark: dark), ground(of: second, dark: dark))
                let accentGap = colourDistance(first.accentHex(dark: dark), second.accentHex(dark: dark))
                #expect(
                    groundGap + accentGap >= 22,
                    "\(first) and \(second) \(dark ? "dark" : "light"): ground \(groundGap), accent \(accentGap)"
                )
            }
        }
    }

    @Test("the themes read as three ingredients and then the bowl they are pounded in")
    func whenListed_thenIngredientsThenMortar() {
        #expect(AppTheme.allCases == [.basil, .parmesan, .pineNut, .mortar])
    }

    @Test("Mortar's light ground is cool marble: a different temperature from Basil's cream, not just another accent")
    func whenMortarLight_thenGroundIsCoolMarble() {
        #expect(ground(of: .mortar, dark: false) == "E0E2E0")
    }

    @Test("Mortar and Basil differ in the ground itself, in light and in dark")
    func whenMortarAndBasil_thenGroundsDifferPlainly() {
        for dark in [false, true] {
            let gap = colourDistance(ground(of: .mortar, dark: dark), ground(of: .basil, dark: dark))
            #expect(gap >= 6, "\(dark ? "dark" : "light"): \(gap)")
        }
    }

    @Test("a tint stays a wash: the shelf is still glass underneath")
    func whenAnyTheme_thenTintOpacityIsModest() {
        for theme in AppTheme.allCases {
            for dark in [false, true] {
                #expect((theme.tint(dark: dark)?.opacity ?? 0) <= 0.6, "\(theme)")
            }
        }
    }

    @Test("every theme names the icon that goes with it, and the names are distinct")
    func whenAnyTheme_thenHasAPairedIconAndAName() {
        #expect(AppTheme.basil.pairedIcon == .basil)
        #expect(AppTheme.parmesan.pairedIcon == .parmesan)
        #expect(AppTheme.pineNut.pairedIcon == .pineNut)
        #expect(AppTheme.mortar.pairedIcon == .mortar)
        #expect(Set(AppTheme.allCases.map(\.displayName)).count == AppTheme.allCases.count)
    }

    @Test("choosing a theme sets its icon and puts the accent back on the brand colour")
    func whenThemeChosen_thenIconAndAccentFollow() {
        let result = AppTheme.mortar.applied()

        #expect(result.theme == "mortar")
        #expect(result.icon == AppIconChoice.mortar.rawValue)
        #expect(result.accent == AccentChoice.defaultStored)
    }

    @Test("the theme is a registered setting that defaults to Basil")
    func whenSettingRead_thenBasilIsDefaultAndKeyIsRegistered() {
        #expect(Setting.appTheme.defaultValue == AppTheme.basil.rawValue)
        #expect(Setting.allNames.contains(Setting.appTheme.name))
    }
}

private extension Array {
    func pairs() -> [(Element, Element)] {
        indices.flatMap { i in indices.filter { $0 > i }.map { (self[i], self[$0]) } }
    }
}

@Suite("A theme for each appearance")
struct AppThemePerModeTests {
    @Test("with no dark theme chosen, both appearances use the one theme")
    func whenNoDarkTheme_thenTheSameTheme() {
        #expect(AppTheme.resolve(light: "parmesan", dark: "", isDark: false) == .parmesan)
        #expect(AppTheme.resolve(light: "parmesan", dark: "", isDark: true) == .parmesan)
    }

    @Test("a dark theme applies in dark appearance only")
    func whenDarkThemeChosen_thenItAppliesInDarkOnly() {
        #expect(AppTheme.resolve(light: "parmesan", dark: "mortar", isDark: false) == .parmesan)
        #expect(AppTheme.resolve(light: "parmesan", dark: "mortar", isDark: true) == .mortar)
    }

    @Test("a stored value that is not a theme falls back to the light theme, never to a surprise")
    func whenDarkValueIsGarbage_thenLightThemeApplies() {
        #expect(AppTheme.resolve(light: "pineNut", dark: "zzz", isDark: true) == .pineNut)
        #expect(AppTheme.resolve(light: "zzz", dark: "", isDark: false) == .basil)
    }

    @Test("the dark theme is a registered setting that starts empty")
    func whenRegistered_thenEmptyByDefault() {
        #expect(Setting.appThemeDark.defaultValue.isEmpty)
        #expect(Setting.allNames.contains(Setting.appThemeDark.name))
    }
}
