// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import os

/// Tier 1 of the paste strategy. Writes a string directly to the target app's
/// `AXFocusedUIElement` via the Accessibility API. See ADR 0009.
///
/// Faster and more reliable than `CGEvent.post`-ing a Cmd+V for text targets that
/// expose Accessibility (most native macOS apps). Returns `false` silently when the
/// target element doesn't support direct value writing, so the paste coordinator can
/// fall back to Tier 2.
public struct AccessibilityWriter: Sendable {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AccessibilityWriter")

    public init() {}

    public var hasAccessibility: Bool {
        AccessibilityAccess.isTrusted
    }

    /// Attempts to write `text` into the focused UI element of the app with PID `pid`.
    /// Returns true on success, false if direct write isn't supported.
    public func write(text: String, to pid: pid_t, caretOffsetFromEnd: Int? = nil) -> Bool {
        guard hasAccessibility else {
            Self.logger.debug("AX direct write skipped — Accessibility not granted")
            return false
        }

        let app = AXUIElementCreateApplication(pid)
        AccessibilityTimeout.apply(to: app)

        var focused: AnyObject?
        let focusStatus = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusStatus == .success, let focused, let focusedElement = AXCast.element(focused) else {
            Self.logger.debug("AX direct write: no focused element (status \(focusStatus.rawValue))")
            return false
        }
        AccessibilityTimeout.apply(to: focusedElement)

        // Check whether the element actually supports a settable value.
        var settable: DarwinBoolean = false
        let settableStatus = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &settable
        )
        guard settableStatus == .success, settable.boolValue else {
            Self.logger.debug("AX direct write: value not settable on focused element")
            return false
        }

        // Insert at the selection point. If the element doesn't expose a selection range
        // or the insert fails, return false — Tier 2 (CGEvent Cmd+V) handles it.
        // We deliberately do NOT fall back to setting kAXValueAttribute, which replaces
        // the entire field content and would destroy any existing text.
        if insertAtSelection(text: text, in: focusedElement, caretOffsetFromEnd: caretOffsetFromEnd) { return true }
        Self.logger.debug("AX direct write: insertAtSelection failed, deferring to Tier 2")
        return false
    }

    private func insertAtSelection(text: String, in element: AXUIElement, caretOffsetFromEnd: Int?) -> Bool {
        TextInsertion.insert(
            text, into: AXElementTextTarget(element: element), caretOffsetFromEnd: caretOffsetFromEnd
        )
    }
}

private struct AXElementTextTarget: AXTextTarget, @unchecked Sendable {
    /// AXUIElement is not Sendable, but the target lives only for one synchronous insertion.
    let element: AXUIElement

    func selectedRange() -> CFRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value else { return nil }
        guard let axValue = AXCast.value(value) else { return nil }
        var range = CFRange(location: 0, length: 0)
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    func characterCount() -> Int? {
        var value: AnyObject?
        let key = kAXNumberOfCharactersAttribute as CFString
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    func setSelectedText(_ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    func setSelectedRange(_ range: CFRange) {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return }
        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }
}
