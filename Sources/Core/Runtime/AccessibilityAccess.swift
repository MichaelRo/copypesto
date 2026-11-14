// SPDX-License-Identifier: MIT
#if os(macOS)
import ApplicationServices
import Foundation
import Synchronization

/// The single access point for the Accessibility permission. Under UI test the state is stubbed, so a
/// run needs no real grant and never shows the system prompt.
public enum AccessibilityAccess {
    private static let uiTestOverride = Mutex<AccessibilityStub?>(nil)

    public static var isTrusted: Bool {
        isTrusted(for: RuntimeConfiguration.current)
    }

    public static func setUITestOverride(_ stub: AccessibilityStub?) {
        uiTestOverride.withLock { $0 = stub }
    }

    public static func requestWithPrompt() {
        guard mayPrompt(for: RuntimeConfiguration.current) else { return }
        // Avoid `kAXTrustedCheckOptionPrompt` (extern var, not Sendable in Swift 6); the literal key is stable.
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt" as CFString: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func isTrusted(for configuration: RuntimeConfiguration) -> Bool {
        guard configuration.mode == .uiTest else { return AXIsProcessTrusted() }
        let stub = uiTestOverride.withLock { $0 } ?? configuration.accessibility
        return stub == .trusted
    }

    static func mayPrompt(for configuration: RuntimeConfiguration) -> Bool {
        configuration.mode == .normal
    }
}
#endif
