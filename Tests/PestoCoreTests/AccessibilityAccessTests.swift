// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("AccessibilityAccess")
struct AccessibilityAccessTests {
    private func configuration(mode: LaunchMode, accessibility: AccessibilityStub) -> RuntimeConfiguration {
        RuntimeConfiguration(mode: mode, session: "default", seed: .basic, accessibility: accessibility)
    }

    @Test("a uiTest launch reports the stubbed state, whatever the real system says")
    func whenUITest_thenStubbedState() {
        #expect(AccessibilityAccess.isTrusted(for: configuration(mode: .uiTest, accessibility: .trusted)))
        #expect(!AccessibilityAccess.isTrusted(for: configuration(mode: .uiTest, accessibility: .denied)))
    }

    @Test("only a normal launch may show the system permission prompt")
    func whenNotNormal_thenNeverPrompts() {
        #expect(AccessibilityAccess.mayPrompt(for: configuration(mode: .normal, accessibility: .trusted)))
        #expect(!AccessibilityAccess.mayPrompt(for: configuration(mode: .uiTest, accessibility: .denied)))
        #expect(!AccessibilityAccess.mayPrompt(for: configuration(mode: .hostedTests, accessibility: .trusted)))
    }
}
