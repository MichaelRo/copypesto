// SPDX-License-Identifier: MIT
import ApplicationServices
import Foundation

/// The single access point for the Accessibility permission. Under UI test the state is stubbed, so a
/// run needs no real grant and never shows the system prompt.
public enum AccessibilityAccess {
    public static var isTrusted: Bool {
        isTrusted(for: RuntimeConfiguration.current)
    }

    public static func requestWithPrompt() {
        guard mayPrompt(for: RuntimeConfiguration.current) else { return }
        // Avoid `kAXTrustedCheckOptionPrompt` (extern var, not Sendable in Swift 6); the literal key is stable.
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt" as CFString: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func isTrusted(for configuration: RuntimeConfiguration) -> Bool {
        configuration.mode == .uiTest ? configuration.accessibility == .trusted : AXIsProcessTrusted()
    }

    static func mayPrompt(for configuration: RuntimeConfiguration) -> Bool {
        configuration.mode == .normal
    }
}
