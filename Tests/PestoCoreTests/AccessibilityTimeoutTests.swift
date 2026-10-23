// SPDX-License-Identifier: MIT
import ApplicationServices
import Foundation
import Testing
@testable import PestoCore

@Suite("Accessibility messaging timeout")
struct AccessibilityTimeoutTests {
    @Test("the timeout is short enough that a hung app cannot freeze a paste for seconds")
    func timeoutIsShort() {
        #expect(AccessibilityTimeout.seconds > 0)
        #expect(AccessibilityTimeout.seconds <= 1)
    }

    @Test("applying it to an element does not fail")
    func applyingDoesNotCrash() {
        AccessibilityTimeout.apply(to: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier))
    }
}
