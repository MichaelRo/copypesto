// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The badge a hidden card carries")
struct SensitivityBadgeTests {
    @Test("an API key or token reads Token, not the jargon OAuth")
    func whenAKeyIsHidden_thenTheBadgeIsAPlainWord() {
        let anthropicKey = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789"
        let result = SensitiveContentDetector.detect(in: anthropicKey)

        #expect(result?.category == .oauthToken)
        #expect(result?.category.badgeLabel == "Token")
    }

    @Test("every category has a short plain badge")
    func everyCategory_hasABadgeOfOneOrTwoWords() {
        for category in SensitivityCategory.allCases {
            let words = category.badgeLabel.split(separator: " ")
            #expect((1...2).contains(words.count), "\(category)")
            #expect(!category.badgeLabel.contains("OAuth"), "\(category)")
        }
    }

    @Test("a hidden token is still found by typing OAuth")
    func searchStillKnowsTheOldWord() {
        #expect(SensitivityCategory.oauthToken.searchName.contains("OAuth"))
        #expect(SensitivityCategory.oauthToken.searchName.contains("Token"))
    }
}
