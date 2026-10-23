// SPDX-License-Identifier: MIT
import Foundation

/// What launch does about onboarding. The flag is part of the decision: the preferences can survive what a person
/// considers a fresh install, but a person who has not onboarded must see it even when Accessibility is still granted
/// (resetting only the flag used to show nothing). A missing key shows it whatever the flag says.
public enum OnboardingGate {
    public enum Action: Equatable, Sendable {
        case showOnboarding
        case promptForAccessibility
        case nothing
    }

    public static func action(
        keyAvailable: Bool, hasOnboarded: Bool, accessibilityTrusted: Bool, declinedAutoPaste: Bool = false
    )
    -> Action {
        if !keyAvailable || !hasOnboarded { return .showOnboarding }
        return accessibilityTrusted || declinedAutoPaste ? .nothing : .promptForAccessibility
    }
}
