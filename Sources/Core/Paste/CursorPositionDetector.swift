// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

/// Queries the Accessibility API for the screen-space bounds of the current text selection cursor.
///
/// Returns a `CGRect` in Cocoa screen coordinates (origin at bottom-left of main screen),
/// suitable for positioning an `NSWindow` just above the insertion point.
///
/// Returns `nil` when:
/// - The frontmost app has no focused text field, or
/// - The app has not granted Accessibility permission, or
/// - The element doesn't expose `kAXBoundsForRangeParameterizedAttribute`.
public enum CursorPositionDetector {
    public static func cursorRect(for pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        // Runs on the main actor while the shelf opens: an app that does not answer must not hold the hotkey.
        AccessibilityTimeout.apply(to: app)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return nil }

        guard let element = AXCast.element(focusedRef) else { return nil }
        AccessibilityTimeout.apply(to: element)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success, let boundsRef else { return nil }

        guard let axValue = AXCast.value(boundsRef) else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }

        guard !rect.isEmpty else { return nil }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return ScreenCoordinates.cocoaRect(fromAX: rect, primaryScreenHeight: primaryHeight)
    }
}
