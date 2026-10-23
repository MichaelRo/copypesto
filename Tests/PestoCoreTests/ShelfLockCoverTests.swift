// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What the locked shelf hides and the destructive fill (D-01, A-09)")
struct ShelfLockCoverTests {
    @Test("the lock blur is wide enough that the smallest text on the shelf cannot be read through it")
    func whenLocked_thenSmallestTextIsUnreadable() {
        #expect(ShelfLockCover.hidesSmallestText)
        #expect(ShelfLockCover.blurRadius > 10, "a radius of 10 left chip names and picture shapes readable")
    }

    @Test("white on the destructive fill reads at 4.5:1 in light and dark", arguments: [
        DestructiveFill.lightHex, DestructiveFill.darkHex
    ])
    func whenDestructiveFill_thenWhiteLabelIsReadable(fill: String) {
        #expect(ContrastRatio.between("FFFFFF", fill) >= 4.5)
    }
}
