// SPDX-License-Identifier: MIT
import ApplicationServices

/// A hung target app would otherwise block an Accessibility call for the system default of several seconds.
enum AccessibilityTimeout {
    static let seconds: Float = 0.5

    static func apply(to element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }
}
