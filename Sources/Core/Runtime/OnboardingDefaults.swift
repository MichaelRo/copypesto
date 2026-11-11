// SPDX-License-Identifier: MIT
import Foundation

public enum OnboardingDefaults {
    public static func applyOnce(
        defaults: UserDefaults = AppDefaults.store,
        isLive: Bool = LaunchMode.current.usesSystemIntegrations
    ) {
        guard isLive, !defaults.value(for: Setting.onboardingDefaultsOffered) else { return }
        // Marked even when onboarding was already done so a returning install never gets prompted defaults later.
        defer { defaults.set(true, for: Setting.onboardingDefaultsOffered) }
        guard !defaults.value(for: Setting.hasOnboarded) else { return }
        if !defaults.hasValue(for: Setting.linkPreviews) {
            defaults.set(true, for: Setting.linkPreviews)
        }
        if !defaults.hasValue(for: Setting.keepsRemoteCopies) {
            defaults.set(true, for: Setting.keepsRemoteCopies)
        }
    }
}
