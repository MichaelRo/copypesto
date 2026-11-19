// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What an AI action is called")
struct AIActionTitleTests {
    @Test("every action has a title, which in English is its stored name")
    func whenTitled_thenEnglishIsTheName() {
        for action in AIAction.allCases {
            #expect(String(localized: action.title) == action.rawValue)
        }
    }
}
