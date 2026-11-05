// SPDX-License-Identifier: MIT
import Foundation

/// Setup's last step offers "Launch Pesto at login" already on (ADR 0024). It is turned on once, here, and the person's
/// answer is theirs after that: a Mac that was offered it, or has it off, is never turned on again by this.
public enum LoginItemSetupDefault {
    public static func shouldEnable(status: LoginItemStatus, alreadyOffered: Bool) -> Bool {
        !alreadyOffered && status == .disabled
    }

    /// Records the offer even when macOS refuses (an app outside Applications), so it is not retried on every visit.
    public static func applyOnce(service: LoginItemService, defaults: UserDefaults = AppDefaults.store) {
        let offered = defaults.value(for: Setting.loginItemOffered)
        defer { defaults.set(true, for: Setting.loginItemOffered) }
        guard shouldEnable(status: service.status, alreadyOffered: offered) else { return }
        service.setEnabled(true)
    }
}
