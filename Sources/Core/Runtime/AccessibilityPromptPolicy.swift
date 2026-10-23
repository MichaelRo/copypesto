// SPDX-License-Identifier: MIT
public enum AccessibilityPromptPolicy {
    public static let defaultsKey = "accessibilityPromptedVersion"

    /// The system dialog on every launch nags users who chose to go without auto-paste.
    public static func shouldPrompt(lastPromptedVersion: String?, currentVersion: String) -> Bool {
        lastPromptedVersion != currentVersion
    }
}
