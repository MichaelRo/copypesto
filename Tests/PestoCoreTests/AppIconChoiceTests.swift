// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("App icon choice")
struct AppIconChoiceTests {
    @Test("a fresh install uses Basil, the icon the app bundle carries")
    func whenUntouched_thenBasil() {
        #expect(Setting.appIcon.defaultValue == AppIconChoice.basil.rawValue)
        #expect(AppIconChoice(stored: Setting.appIcon.defaultValue) == .basil)
        #expect(AppIconChoice.basil.dockImageName == nil, "Basil is the bundle icon: nothing replaces it")
    }

    @Test("Parmesan, Pine nut and Mortar replace the Dock icon with their own picture")
    func whenAlternate_thenNamedImage() {
        #expect(AppIconChoice.parmesan.dockImageName == "AppIconParmesan")
        #expect(AppIconChoice.pineNut.dockImageName == "AppIconPineNut")
        #expect(AppIconChoice.mortar.dockImageName == "AppIconMortar")
    }

    @Test("each icon is named after the theme it goes with, in the themes' order")
    func whenListed_thenNamedAfterTheThemes() {
        #expect(AppIconChoice.allCases.map(\.displayName) == AppTheme.allCases.map(\.displayName))
        #expect(AppIconChoice.allCases == [.basil, .parmesan, .pineNut, .mortar])
    }

    @Test("a stored Gold or Garlic, from before the icons took their theme's name, reads as Parmesan or Pine nut")
    func whenLegacyName_thenItsThemeIcon() {
        #expect(AppIconChoice(stored: "gold") == .parmesan)
        #expect(AppIconChoice(stored: "garlic") == .pineNut)
        #expect(AppIconChoice.acceptedStoredValues.isSuperset(of: ["gold", "garlic"]))
        #expect(AppIconChoice.acceptedStoredValues.isSuperset(of: AppIconChoice.allCases.map(\.rawValue)))
    }

    @Test("an unknown stored value falls back to Basil")
    func whenUnknown_thenBasil() {
        #expect(AppIconChoice(stored: "teal") == .basil)
        #expect(AppIconChoice(stored: "") == .basil)
    }

    @Test("every choice has a name to show, and a picture to preview")
    func whenListed_thenNamedAndPictured() {
        for choice in AppIconChoice.allCases {
            #expect(!choice.displayName.isEmpty)
            #expect(choice.previewImageName.lowercased() == "appicon" + choice.displayName.filter { !$0.isWhitespace }
                .lowercased())
        }
        #expect(Setting.allNames.contains(Setting.appIcon.name))
    }
}
