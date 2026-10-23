// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("OnboardingGate")
struct OnboardingGateTests {
    @Test("a missing encryption key always shows onboarding")
    func whenNoKey_thenOnboarding() {
        #expect(OnboardingGate
            .action(keyAvailable: false, hasOnboarded: true, accessibilityTrusted: true) == .showOnboarding)
        #expect(OnboardingGate
            .action(keyAvailable: false, hasOnboarded: false, accessibilityTrusted: false) == .showOnboarding)
    }

    @Test("a person who has not onboarded sees it even when Accessibility was granted earlier")
    func whenNotOnboarded_thenOnboardingEvenWithAccessibility() {
        #expect(OnboardingGate
            .action(keyAvailable: true, hasOnboarded: false, accessibilityTrusted: true) == .showOnboarding)
        #expect(OnboardingGate
            .action(keyAvailable: true, hasOnboarded: false, accessibilityTrusted: false) == .showOnboarding)
    }

    @Test("an onboarded person who lost Accessibility is prompted, not sent back through onboarding")
    func whenOnboardedWithoutAccessibility_thenPromptOnly() {
        #expect(OnboardingGate
            .action(keyAvailable: true, hasOnboarded: true, accessibilityTrusted: false) == .promptForAccessibility)
    }

    @Test("everything in place shows nothing")
    func whenHealthy_thenNothing() {
        #expect(OnboardingGate.action(keyAvailable: true, hasOnboarded: true, accessibilityTrusted: true) == .nothing)
    }

    @Test("someone who chose to go without auto-paste is not asked again after an update")
    func whenAutoPasteWasDeclined_thenNoPrompt() {
        #expect(OnboardingGate.action(
            keyAvailable: true, hasOnboarded: true, accessibilityTrusted: false, declinedAutoPaste: true
        ) == .nothing)
        #expect(OnboardingGate.action(
            keyAvailable: true, hasOnboarded: true, accessibilityTrusted: false, declinedAutoPaste: false
        ) == .promptForAccessibility)
    }

    @Test("a declined choice never hides onboarding itself")
    func whenDeclinedButNotOnboarded_thenOnboarding() {
        #expect(OnboardingGate.action(
            keyAvailable: true, hasOnboarded: false, accessibilityTrusted: false, declinedAutoPaste: true
        ) == .showOnboarding)
    }
}
