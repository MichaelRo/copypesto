// SPDX-License-Identifier: MIT
import Foundation
#if os(macOS)
    import ApplicationServices
#endif

/// Reads the focused text selection from another app on demand when a snippet contains `{{selection}}`.
public protocol SelectedTextReading: Sendable {
    @MainActor
    func selectedText(inProcess pid: pid_t) -> String
}

/// Reads `kAXSelectedTextAttribute` on the target app's focused UI element with an IPC timeout and no retention.
public struct SystemSelectedTextReader: SelectedTextReading {
    private static let maxCharacters = 100_000

    public init() {}

    @MainActor
    public func selectedText(inProcess pid: pid_t) -> String {
        #if os(macOS)
            guard AccessibilityAccess.isTrusted else { return "" }

            let application = AXUIElementCreateApplication(pid)
            AccessibilityTimeout.apply(to: application)

            var rawFocus: AnyObject?
            let focusStatus = AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute as CFString,
                &rawFocus
            )
            guard focusStatus == .success, let rawFocus, let focused = AXCast.element(rawFocus) else {
                return ""
            }
            AccessibilityTimeout.apply(to: focused)

            var rawSubrole: AnyObject?
            if AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &rawSubrole) == .success,
               (rawSubrole as? String) == kAXSecureTextFieldSubrole
            {
                return ""
            }

            var rawText: AnyObject?
            let textStatus = AXUIElementCopyAttributeValue(
                focused,
                kAXSelectedTextAttribute as CFString,
                &rawText
            )
            guard textStatus == .success, let text = rawText as? String, !text.isEmpty else {
                return ""
            }

            return text.count <= Self.maxCharacters ? text : String(text.prefix(Self.maxCharacters))
        #else
            return ""
        #endif
    }
}
