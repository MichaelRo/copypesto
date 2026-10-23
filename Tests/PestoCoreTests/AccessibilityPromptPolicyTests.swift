// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("AccessibilityPromptPolicy")
struct AccessibilityPromptPolicyTests {
    @Test("never prompted before: prompt")
    func whenNeverPrompted_thenPrompt() {
        #expect(AccessibilityPromptPolicy.shouldPrompt(lastPromptedVersion: nil, currentVersion: "1.0"))
    }

    @Test("already prompted for this version: stay quiet on later launches")
    func whenPromptedThisVersion_thenQuiet() {
        #expect(!AccessibilityPromptPolicy.shouldPrompt(lastPromptedVersion: "1.0", currentVersion: "1.0"))
    }

    @Test("a new version may prompt once more")
    func whenNewVersion_thenPromptAgain() {
        #expect(AccessibilityPromptPolicy.shouldPrompt(lastPromptedVersion: "1.0", currentVersion: "1.1"))
    }
}
