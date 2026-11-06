// SPDX-License-Identifier: MIT
import Foundation

/// Setup's last step offers "Launch Pesto at login" already on (ADR 0024). It is turned on once, here, and the person's
/// answer is theirs after that: a Mac that was offered it, has it off, or finished setup before this existed is never
/// turned on again by this.
public enum LoginItemSetupDefault {
    public static func shouldEnable(status: LoginItemStatus, alreadyOffered: Bool, hasOnboarded: Bool) -> Bool {
        !alreadyOffered && !hasOnboarded && status == .disabled
    }

    /// Records the offer even when macOS refuses (an app outside Applications), so it is not retried on every visit,
    /// and returns the refusal so the step can show it. Nil when nothing was attempted: a UI-test or hosted-test
    /// launch is never live.
    @discardableResult
    public static func applyOnce(
        service: LoginItemService,
        defaults: UserDefaults = AppDefaults.store,
        isLive: Bool = LaunchMode.current.usesSystemIntegrations
    )
    -> LoginItemChange? {
        guard isLive else { return nil }
        let offered = defaults.value(for: Setting.loginItemOffered)
        defer { defaults.set(true, for: Setting.loginItemOffered) }
        let hasOnboarded = defaults.value(for: Setting.hasOnboarded)
        guard shouldEnable(status: service.status, alreadyOffered: offered, hasOnboarded: hasOnboarded) else {
            return nil
        }
        return service.setEnabled(true)
    }
}
