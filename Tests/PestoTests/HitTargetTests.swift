// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing
@testable import Pesto

@Suite("Hit targets (A-10)")
@MainActor
struct HitTargetTests {
    private func size(of view: some View) -> CGSize {
        NSHostingController(rootView: view).view.fittingSize
    }

    @Test("a 10 pt glyph in a button is still a 24 pt target")
    func whenSmallGlyph_thenTargetIsAtLeast24() {
        let bare = size(of: Image(systemName: "xmark").font(.system(size: 10)))
        let target = size(of: Image(systemName: "xmark").font(.system(size: 10)).pestoHitTarget())

        #expect(bare.width < 24 && bare.height < 24, "control: the bare glyph is smaller than a target")
        #expect(target.width >= 24 && target.height >= 24)
    }

    @Test("the side can be larger, for the controls drawn bigger")
    func whenSideGiven_thenItIsUsed() {
        let target = size(of: Image(systemName: "xmark").pestoHitTarget(28))
        #expect(target.width >= 28 && target.height >= 28)
    }
}
