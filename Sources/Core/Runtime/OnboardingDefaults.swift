// SPDX-License-Identifier: MIT
import Foundation

public enum OnboardingDefaults {
    public static func applyOnce(
        defaults: UserDefaults = AppDefaults.store,
        isLive: Bool = LaunchMode.current.usesSystemIntegrations
    ) {
        guard isLive, !defaults.value(for: Setting.onboardingDefaultsOffered) else { return }
        defer { defaults.set(true, for: Setting.onboardingDefaultsOffered) }
        guard !defaults.value(for: Setting.hasOnboarded) else { return }
        defaults.set(true, for: Setting.linkPreviews)
        defaults.set(true, for: Setting.keepsRemoteCopies)
    }
}
