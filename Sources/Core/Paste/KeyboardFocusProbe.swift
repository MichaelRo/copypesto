// SPDX-License-Identifier: MIT
import ApplicationServices
import Foundation

/// Which process a keystroke would go to right now. The shelf is a panel that takes the keyboard without taking the
/// front, so after it closes the target app is already frontmost but its window is not key until the window server has
/// handed the keyboard back; a ⌘V posted before that is silently dropped. This is the system's own answer, so the paste
/// waits for exactly that and no longer.
public protocol KeyboardFocusProbing: Sendable {
    /// The process that has the keyboard, or nil when the system will not say (no Accessibility permission).
    func focusedProcess() -> pid_t?
}

public struct SystemKeyboardFocusProbe: KeyboardFocusProbing {
    public init() {}

    public func focusedProcess() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        AccessibilityTimeout.apply(to: system)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focused) == .success,
              let focused, let application = AXCast.element(focused) else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(application, &pid) == .success ? pid : nil
    }
}
