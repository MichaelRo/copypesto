// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoMobile

@Suite("The grid keeps still while the person looks at it")
@MainActor
struct GridOrderTests {
    private let ids = (0..<4).map { _ in UUID() }

    @Test("a clip moved to the front by a copy stays where it was drawn")
    func whenACopyMovesAClip_thenTheGridKeepsItsPlace() {
        let order = GridOrder()
        #expect(order.arrange(ids, context: "all") == ids)

        let afterCopy = [ids[2], ids[0], ids[1], ids[3]]
        #expect(order.arrange(afterCopy, context: "all") == ids)
    }

    @Test("a new clip appears at the top, and a deleted one goes")
    func whenClipsArriveOrGo_thenTheyAreShownAtTheTopOrDropped() {
        let order = GridOrder()
        _ = order.arrange(ids, context: "all")
        let arrived = UUID()

        let next = order.arrange([arrived, ids[3], ids[0], ids[2]], context: "all")

        #expect(next == [arrived, ids[0], ids[2], ids[3]])
    }

    @Test("a resort, or another scope or search, takes the history's order")
    func whenResortedOrContextChanges_thenTheFreshOrderIsShown() {
        let order = GridOrder()
        _ = order.arrange(ids, context: "all")
        let afterCopy = [ids[3], ids[0], ids[1], ids[2]]
        #expect(order.arrange(afterCopy, context: "all") == ids)

        order.resort()
        #expect(order.arrange(afterCopy, context: "all") == afterCopy)

        let reordered = [ids[1], ids[3], ids[0], ids[2]]
        #expect(order.arrange(reordered, context: "pinned") == reordered)
    }
}
