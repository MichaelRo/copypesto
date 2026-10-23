// SPDX-License-Identifier: MIT
public enum DoubleCopyPolicy {
    public static let defaultsKey = Setting.doubleCopyAppend.name

    /// A global keyDown monitor sees every keystroke system-wide, so it exists only while the feature is on.
    public static func shouldObserveKeystrokes(enabled: Bool, systemIntegrations: Bool) -> Bool {
        enabled && systemIntegrations
    }

    /// A monitor made before Accessibility was granted may never see an event, so one made untrusted is replaced as
    /// soon as the grant arrives.
    public static func needsReinstall(installedWhileTrusted: Bool, trustedNow: Bool) -> Bool {
        trustedNow && !installedWhileTrusted
    }
}
