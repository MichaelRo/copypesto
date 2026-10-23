// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The settings registry agrees with the types the Settings panes use")
struct SettingDefaultsAgreeTests {
    @Test("the defaults named in Setting are the enums' own first choices")
    func whenComparing_thenDefaultsMatch() {
        #expect(Setting.cardSize.defaultValue == CardSize.large.rawValue)
        #expect(Setting.appearanceMode.defaultValue == AppearanceMode.system.rawValue)
        #expect(CardSize(rawValue: Setting.cardSize.defaultValue) != nil)
        #expect(AppearanceMode(rawValue: Setting.appearanceMode.defaultValue) != nil)
        #expect(Setting.nsfwMode.defaultValue == NSFWMode.blur.rawValue)
    }
}
