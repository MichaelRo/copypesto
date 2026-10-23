// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("GridSelection")
struct GridSelectionTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test("toggle selects, then deselects")
    func whenToggledTwice_thenEmpty() {
        var selection = GridSelection()

        selection.toggle(a)
        #expect(selection.contains(a))
        selection.toggle(a)

        #expect(selection.isEmpty)
    }

    @Test("select all takes exactly what is visible, replacing anything selected before")
    func whenSelectAll_thenOnlyVisibleSelected() {
        var selection = GridSelection()
        selection.toggle(c)

        selection.selectAll([a, b])

        #expect(selection.count == 2 && selection.contains(a) && selection.contains(b) && !selection.contains(c))
    }

    @Test("ordered follows the visible list, not the order of selection")
    func whenSelectedOutOfOrder_thenOrderedByVisibleList() {
        var selection = GridSelection()
        selection.toggle(c)
        selection.toggle(a)

        #expect(selection.ordered(in: [a, b, c]) == [a, c])
    }

    @Test("items that left the list are not returned, so a shifted list cannot select the wrong item")
    func whenListChanges_thenSelectionFollowsItemsNotPositions() {
        var selection = GridSelection()
        selection.toggle(b)

        // A new item lands at index 0: b moves from index 0 to index 1.
        let after = [c, b]

        #expect(selection.ordered(in: after) == [b])
    }

    @Test("prune drops ids that are no longer visible")
    func whenPruned_thenOnlyVisibleRemain() {
        var selection = GridSelection()
        selection.toggle(a)
        selection.toggle(b)

        selection.prune(keeping: [b, c])

        #expect(selection.count == 1)
        #expect(selection.contains(b))
    }

    @Test("clear empties the selection")
    func whenCleared_thenEmpty() {
        var selection = GridSelection()
        selection.toggle(a)

        selection.clear()

        #expect(selection.isEmpty)
    }
}
