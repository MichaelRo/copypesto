// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
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

    @Test("a chip that shows its name on hover keeps the width it has at rest, so neighbors do not move")
    func whenAppChipPeeks_thenItsLayoutWidthIsUnchanged() {
        let rest = PestoChip(
            label: "Safari", icon: "app.badge.checkmark", isActive: false, collapsesLabel: true, action: {}
        )
        let peeking = PestoChip(
            label: "Safari", icon: "app.badge.checkmark", isActive: false, collapsesLabel: true,
            startsPeeking: true, action: {}
        )

        #expect(width(of: peeking, proposing: 600) == width(of: rest, proposing: 600))
    }

    @Test("app chips collapse their labels at rest only when collections are present on the command bar")
    func whenCollectionsAreAbsent_thenAppChipsShowNamesAtRest() {
        let withCollections = AppChipsRow(
            recent: [SourceApp(bundleID: "com.apple.Safari", name: "Safari")],
            frontmost: nil,
            collapsesLabels: true
        ).environment(AppState())
        let withoutCollections = AppChipsRow(
            recent: [SourceApp(bundleID: "com.apple.Safari", name: "Safari")],
            frontmost: nil,
            collapsesLabels: false
        ).environment(AppState())

        let collapsedWidth = NSHostingController(rootView: withCollections)
            .sizeThatFits(in: CGSize(width: 600, height: 100)).width
        let expandedWidth = NSHostingController(rootView: withoutCollections)
            .sizeThatFits(in: CGSize(width: 600, height: 100)).width

        #expect(collapsedWidth <= 30)
        #expect(expandedWidth > collapsedWidth + 20)
    }

    @Test("a collection chip always shows its title at rest and matches PestoChip's 24 pt height")
    func whenCollectionChip_thenTitleIsAlwaysShownAtRestAndMatchesAppChipHeight() {
        let unselected = NSHostingController(
            rootView: CollectionChip(name: "Pesto night", symbolName: "party.popper", color: .red, isSelected: false)
        ).sizeThatFits(in: CGSize(width: 600, height: 100))
        let selected = NSHostingController(
            rootView: CollectionChip(name: "Pesto night", symbolName: "party.popper", color: .red, isSelected: true)
        ).sizeThatFits(in: CGSize(width: 600, height: 100))
        let appChip = NSHostingController(
            rootView: PestoChip(
                label: "Safari", icon: "app.badge.checkmark", isActive: false, collapsesLabel: true, action: {}
            )
        ).sizeThatFits(in: CGSize(width: 600, height: 100))

        #expect(unselected.width > 60, "collection name is visible at rest")
        #expect(abs(unselected.width - selected.width) < 1, "selecting a collection does not change its width")
        #expect(
            abs(unselected.height - appChip.height) < 1,
            "collection chips and app chips share the same 24 pt height"
        )
    }
}
