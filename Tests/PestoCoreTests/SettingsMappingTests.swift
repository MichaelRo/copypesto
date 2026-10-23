// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

/// Each stored setting has to become the behaviour its Settings row promises. These use a private defaults suite per
/// test, so they never read or write the user's preferences.
@Suite("Settings become behaviour")
struct SettingsMappingTests {
    private func suite() -> UserDefaults {
        ThrowawayDefaults.make()
    }

    // MARK: Ingest rules

    @Test("with nothing stored the rules use their documented defaults")
    func whenNothingStored_thenDefaultRules() {
        let rules = ClipboardRules.from(suite())
        #expect(rules.stripTrackingParameters)
        #expect(rules.normalizeLineEndings)
        #expect(!rules.trimWhitespace)
        #expect(!rules.removeDuplicateSpaces)
    }

    @Test("each stored rule toggle turns exactly that rule on or off")
    func whenToggled_thenOnlyThatRuleChanges() {
        let defaults = suite()
        defaults.set(false, forKey: "ruleStripTracking")
        defaults.set(true, forKey: "ruleTrimWhitespace")
        defaults.set(false, forKey: "ruleNormalizeLineEndings")
        defaults.set(true, forKey: "ruleRemoveDuplicateSpaces")

        let rules = ClipboardRules.from(defaults)

        #expect(!rules.stripTrackingParameters)
        #expect(rules.trimWhitespace)
        #expect(!rules.normalizeLineEndings)
        #expect(rules.removeDuplicateSpaces)
    }

    @Test("rules apply to text as their names say", arguments: [
        (
            ClipboardRules(
                stripTrackingParameters: false,
                trimWhitespace: true,
                normalizeLineEndings: false,
                removeDuplicateSpaces: false
            ),
            "  hi  \n",
            "hi"
        ),
        (
            ClipboardRules(
                stripTrackingParameters: false,
                trimWhitespace: false,
                normalizeLineEndings: true,
                removeDuplicateSpaces: false
            ),
            "a\r\nb\rc",
            "a\nb\nc"
        ),
        (
            ClipboardRules(
                stripTrackingParameters: false,
                trimWhitespace: false,
                normalizeLineEndings: false,
                removeDuplicateSpaces: true
            ),
            "a    b   c",
            "a b c"
        ),
        (
            ClipboardRules(
                stripTrackingParameters: true,
                trimWhitespace: false,
                normalizeLineEndings: false,
                removeDuplicateSpaces: false
            ),
            "https://x.io/p?utm_source=a&id=1",
            "https://x.io/p?id=1"
        ),
        (
            ClipboardRules(
                stripTrackingParameters: false,
                trimWhitespace: false,
                normalizeLineEndings: false,
                removeDuplicateSpaces: false
            ),
            "  a\r\nb  c https://x.io/?utm_source=a",
            "  a\r\nb  c https://x.io/?utm_source=a"
        )
    ])
    func whenRuleEnabled_thenTextChanges(rules: ClipboardRules, input: String, expected: String) {
        #expect(rules.apply(to: input) == expected)
    }

    // MARK: Excluded apps

    @Test("the stored exclusion list is split, trimmed and stripped of blanks")
    func whenStoredList_thenParsed() {
        #expect(ExclusionRules.userAdditions(from: " com.a.app , com.b.app ,, \n com.c.app ") == [
            "com.a.app",
            "com.b.app",
            "com.c.app"
        ])
        #expect(ExclusionRules.userAdditions(from: "").isEmpty)
        #expect(ExclusionRules.userAdditions(from: " , ,").isEmpty)
        #expect(ExclusionRules.userAdditions(from: "com.a.app,com.a.app") == ["com.a.app"])
    }

    @Test("a user-added app is excluded and the built-in ones stay excluded")
    func whenUserAddsAnApp_thenBothApply() {
        let rules = ExclusionRules(userAdditions: ExclusionRules.userAdditions(from: "com.example.secret"))
        #expect(rules.shouldIgnore(typeIdentifiers: [], frontmostBundleID: "com.example.secret"))
        #expect(rules.shouldIgnore(typeIdentifiers: [], frontmostBundleID: "com.1password.1password"))
        #expect(!rules.shouldIgnore(typeIdentifiers: [], frontmostBundleID: "com.example.other"))
    }

    // MARK: Filtering mode

    @Test("the content filter defaults to blur and follows the stored mode", arguments: NSFWMode.allCases)
    func whenModeStored_thenCurrent(mode: NSFWMode) {
        let defaults = suite()
        #expect(NSFWMode.current(from: defaults) == .blur)
        defaults.set(mode.rawValue, forKey: NSFWMode.defaultsKey)
        #expect(NSFWMode.current(from: defaults) == mode)
    }
}
