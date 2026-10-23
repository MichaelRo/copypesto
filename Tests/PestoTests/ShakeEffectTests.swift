// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
@testable import Pesto

@Suite("ShakeEffect")
struct ShakeEffectTests {
    @Test("a shake starts and ends where it began, so the glyph never stays off to one side")
    func endsAtRest() {
        for whole in [0, 1, 2, 5] {
            #expect(abs(ShakeEffect.offset(at: CGFloat(whole))) < 0.0001)
        }
    }

    @Test("in between, it moves, and never further than its travel")
    func staysWithinItsTravel() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.01).map { ShakeEffect.offset(at: $0) }

        #expect(samples.contains { abs($0) > 1 }, "the shake does not move")
        #expect(samples.allSatisfy { abs($0) <= ShakeEffect.travel + 0.0001 })
    }
}
