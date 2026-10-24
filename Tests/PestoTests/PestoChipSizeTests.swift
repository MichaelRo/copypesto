// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing
@testable import Pesto

@Suite("A chip is as wide as its label")
@MainActor
struct PestoChipSizeTests {
    private func width(of chip: PestoChip, proposing proposed: CGFloat) -> CGFloat {
        NSHostingController(rootView: chip).sizeThatFits(in: CGSize(width: proposed, height: 100)).width
    }

    @Test("an active chip, with its check mark, is not squeezed when the space offered is narrower", arguments: [
        ("Any time", true), ("Any time", false), ("Yesterday", false), ("ColorSync Utility", true)
    ])
    func whenSpaceIsTight_thenTheChipKeepsItsLabel(label: String, isActive: Bool) {
        let chip = PestoChip(label: label, isActive: isActive, action: {})

        let roomy = width(of: chip, proposing: 600)
        let tight = width(of: chip, proposing: 40)

        #expect(roomy > 40, "the chip has a width at all")
        #expect(tight >= roomy - 0.5, "\(label) was squeezed from \(roomy) to \(tight): its label is cut")
    }

    @Test("a collapsed app chip shows only its icon at rest and opens its name when active or focused")
    func whenCollapsedAppChip_thenCompactAtRestAndExpandsWhenActiveOrFocused() {
        let rest = PestoChip(
            label: "Safari", icon: "app.badge.checkmark", isActive: false, collapsesLabel: true, action: {}
        )
        let active = PestoChip(
            label: "Safari", icon: "app.badge.checkmark", isActive: true, collapsesLabel: true, action: {}
        )
        let focused = PestoChip(
            label: "Safari", icon: "app.badge.checkmark", isActive: false, hasKeyboardCursor: true,
            collapsesLabel: true, action: {}
        )

        let restWidth = width(of: rest, proposing: 600)
        let activeWidth = width(of: active, proposing: 600)
        let focusedWidth = width(of: focused, proposing: 600)

        #expect(restWidth <= 30)
        #expect(activeWidth > restWidth + 20)
        #expect(focusedWidth > restWidth + 20)
    }
}
