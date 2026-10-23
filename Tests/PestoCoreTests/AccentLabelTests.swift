// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Label on an accent fill")
struct AccentLabelTests {
    @Test("the label on every theme and preset accent fill reads at 4.5:1, in light and dark")
    func whenAnyAccentFill_thenItsLabelIsReadable() {
        var fills: [(String, String)] = []
        for dark in [false, true] {
            for theme in AppTheme.allCases {
                fills.append(("\(theme) \(dark ? "dark" : "light")", theme.accentHex(dark: dark)))
            }
            for preset in AccentPreset.allCases {
                fills.append(("\(preset) \(dark ? "dark" : "light")", preset.hex(dark: dark)))
            }
        }
        for (name, fill) in fills {
            let ratio = ContrastRatio.between(ContrastRatio.labelHex(onFill: fill), fill)
            #expect(ratio >= 4.5, "\(name) \(fill): \(ratio)")
        }
    }

    @Test("the dark-mode basil fill takes a dark label, because white on it is about 2:1")
    func whenDarkBasil_thenLabelIsDark() {
        #expect(ContrastRatio.labelHex(onFill: BrandPalette.accentDark) == BrandPalette.mortar)
        #expect(ContrastRatio.labelHex(onFill: BrandPalette.accentLight) == "FFFFFF")
    }

    @Test("a fill that is not a colour gets the white label")
    func whenFillIsNotAColour_thenWhite() {
        #expect(ContrastRatio.labelHex(onFill: "nope") == "FFFFFF")
    }
}
