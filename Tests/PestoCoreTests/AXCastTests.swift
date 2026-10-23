// SPDX-License-Identifier: MIT
import ApplicationServices
import Testing
@testable import PestoCore

@Suite("AXCast")
struct AXCastTests {
    @Test("an accessibility element is accepted as one")
    func whenAnElement_thenItCasts() {
        #expect(AXCast.element(AXUIElementCreateSystemWide()) != nil)
    }

    @Test("a value of another type is refused instead of being treated as an element")
    func whenNotAnElement_thenNil() {
        #expect(AXCast.element("not an element" as CFString) == nil)
        #expect(AXCast.element(AXValueCreate(.cgRect, [CGRect.zero]) as CFTypeRef) == nil)
    }

    @Test("an AXValue is accepted as one, and an element is refused")
    func whenAnAXValue_thenItCasts() {
        var rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let value = AXValueCreate(.cgRect, &rect)

        #expect(value.flatMap { AXCast.value($0) } != nil)
        #expect(AXCast.value(AXUIElementCreateSystemWide()) == nil)
    }
}
