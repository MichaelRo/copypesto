// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Brand palette")
struct BrandPaletteTests {
    @Test("black on white is the maximum contrast, and identical colours have none")
    func whenExtremes_thenKnownRatios() {
        #expect(abs(ContrastRatio.between("000000", "FFFFFF") - 21) < 0.01)
        #expect(abs(ContrastRatio.between("2F7A49", "2F7A49") - 1) < 0.001)
    }

    @Test("accent text reaches AA (4.5) on the light surfaces, and on the dark surface")
    func whenAccentText_thenAA() {
        for background in [BrandPalette.garlic, BrandPalette.parmesan] {
            #expect(ContrastRatio.between(BrandPalette.accentLight, background) >= 4.5, "\(background)")
        }
        #expect(ContrastRatio.between("FFFFFF", BrandPalette.accentLight) >= 4.5, "white label on a filled button")
        #expect(ContrastRatio.between(BrandPalette.accentDark, BrandPalette.darkSurface) >= 4.5)
        #expect(ContrastRatio.between(BrandPalette.darkSurface, BrandPalette.accentDark) >= 4.5, "label on dark accent")
    }

    @Test("body text and gold text also pass on their surfaces")
    func whenTextAndGold_thenAA() {
        #expect(ContrastRatio.between(BrandPalette.mortar, BrandPalette.garlic) >= 7)
        #expect(ContrastRatio.between(BrandPalette.goldTextLight, BrandPalette.garlic) >= 4.5)
        #expect(ContrastRatio.between(BrandPalette.goldTextDark, BrandPalette.mortar) >= 4.5)
        #expect(ContrastRatio.between(BrandPalette.mortar, BrandPalette.goldFill) >= 4.5, "label on a gold fill")
    }

    @Test("a fresh install uses the theme's accent; a name is a preset; any other hex is custom")
    func whenResolving_thenChoice() {
        #expect(AccentChoice.defaultStored == "brand")
        #expect(AccentChoice(stored: "brand") == .brand)
        #expect(AccentChoice(stored: "blue") == .preset(.blue))
        #expect(AccentChoice(stored: "123456") == .custom("123456"))
        #expect(AccentChoice(stored: "abcdef") == .custom("ABCDEF"))
    }

    @Test("the old system accent, which only ever drew blue, becomes the theme's own")
    func whenStoredIsEmpty_thenTheThemesAccent() {
        #expect(AccentChoice(stored: "") == .brand)
    }

    @Test("the system colours earlier versions stored as hex map to the presets that replaced them")
    func whenAnOldHexIsStored_thenItIsThePreset() {
        #expect(AccentChoice(stored: "0A84FF") == .preset(.blue))
        #expect(AccentChoice(stored: "0a84ff") == .preset(.blue))
        #expect(AccentChoice(stored: "BF5AF2") == .preset(.purple))
        #expect(AccentChoice(stored: "FF375F") == .preset(.pink))
        #expect(AccentChoice(stored: "FF9F0A") == .preset(.orange))
    }

    @Test("each choice stores a value that reads back as itself")
    func whenStored_thenRoundTrips() {
        for choice in [AccentChoice.brand, .preset(.red), .custom("123456")] {
            #expect(AccentChoice(stored: choice.stored) == choice)
        }
    }

    @Test("something that is not a colour falls back to the brand accent, never crashes")
    func whenGarbage_thenBrand() {
        #expect(AccentChoice(stored: "zzz") == .brand)
        #expect(AccentChoice(stored: "12345") == .brand)
    }

    @Test("a malformed hex is rejected by the contrast maths rather than crashing")
    func whenBadHex_thenZeroContrast() {
        #expect(ContrastRatio.between("nope", "FFFFFF") == 0)
    }
}

@Suite("Text on accent-tinted chips")
struct TintedChipContrastTests {
    /// Whatever accent a person picks, chip text is the primary text colour on a 25% tint of it, so the text
    /// contrast can never fall below what the surface itself gives.
    private let accents = [
        BrandPalette.accentLight, BrandPalette.accentDark, "0A84FF", "BF5AF2", "FF375F", "FF9F0A", "FFFF00", "FFFFFF",
        "000000", "00FF00", "FF0000", "808080"
    ]

    @Test("primary text on a 25% tint of any accent stays at least 4.5:1 in light appearance")
    func whenLight_thenReadable() {
        for accent in accents {
            let background = ContrastRatio.blend(accent, over: BrandPalette.garlic, alpha: 0.25)
            #expect(ContrastRatio.between(BrandPalette.mortar, background) >= 4.5, "accent \(accent)")
        }
    }

    @Test("primary text on a 25% tint of any accent stays at least 4.5:1 in dark appearance")
    func whenDark_thenReadable() {
        for accent in accents {
            let background = ContrastRatio.blend(accent, over: BrandPalette.darkSurface, alpha: 0.25)
            #expect(ContrastRatio.between(BrandPalette.parmesan, background) >= 4.5, "accent \(accent)")
        }
    }

    @Test("blending is a plain alpha mix of the two colours")
    func whenBlended_thenMidpoint() {
        #expect(ContrastRatio.blend("000000", over: "FFFFFF", alpha: 0.5) == "808080")
        #expect(ContrastRatio.blend("FF0000", over: "0000FF", alpha: 1) == "FF0000")
    }
}

@Suite("Accent presets")
struct AccentPresetTests {
    @Test("each shade reads as text, 4.5:1, on the plain ground of its appearance")
    func whenUsedAsText_thenReadable() {
        for preset in AccentPreset.allCases {
            #expect(ContrastRatio.between(preset.hex(dark: false), BrandPalette.garlic) >= 4.5, "\(preset) light")
            #expect(ContrastRatio.between(preset.hex(dark: true), BrandPalette.darkSurface) >= 4.5, "\(preset) dark")
        }
    }

    @Test("a preset is not mistaken for any theme's own accent")
    func whenComparedWithThemes_thenDistinct() {
        for preset in AccentPreset.allCases {
            for theme in AppTheme.allCases {
                for dark in [false, true] {
                    let distance = Self.distance(preset.hex(dark: dark), theme.accentHex(dark: dark))
                    #expect(distance >= 40, "\(preset) vs \(theme) (dark: \(dark)) is only \(Int(distance)) apart")
                }
            }
        }
    }

    @Test("presets are named once, and the names are how they are stored")
    func whenListed_thenNamesAreUnique() {
        let names = AccentPreset.allCases.map(\.rawValue)

        #expect(Set(names).count == names.count)
        #expect(AccentPreset.allCases.map(\.displayName) == names.map(\.capitalized))
    }

    private static func distance(_ a: String, _ b: String) -> Double {
        func channels(_ hex: String) -> [Double] {
            let value = UInt32(hex, radix: 16) ?? 0
            return [Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF)]
        }
        return zip(channels(a), channels(b)).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }
}

@Suite("App icon order")
struct AppIconOrderTests {
    @Test("the icons are listed in the order of the themes they go with, so a picker lines them up")
    func whenListed_thenFollowsTheThemes() {
        #expect(AppIconChoice.allCases == AppTheme.allCases.map(\.pairedIcon))
    }
}
