// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("The shelf forgets its collection and filters after a while closed")
    @MainActor
    struct ShelfContextMemoryTests {
        private func stateInACollection() -> (AppState, UUID) {
            let state = AppState()
            let collection = UUID()
            state.selectedCollectionID = collection
            state.searchTypeFilter = ["text"]
            state.appChipFilter = ["com.apple.Notes"]
            return (state, collection)
        }

        @Test("reopening soon keeps the collection and the filters")
        func whenReopenedSoon_thenContextKept() {
            let (state, collection) = stateInACollection()
            state.shelfClosedAt = Date(timeIntervalSince1970: 1000)

            state.resetShelfContextIfStale(now: Date(timeIntervalSince1970: 1060), restingCollectionID: nil)

            #expect(state.selectedCollectionID == collection)
            #expect(state.searchTypeFilter == ["text"])
        }

        @Test("reopening after 90 seconds starts from All with no filters")
        func whenReopenedLate_thenContextCleared() {
            let (state, _) = stateInACollection()
            state.shelfClosedAt = Date(timeIntervalSince1970: 1000)

            state.resetShelfContextIfStale(now: Date(timeIntervalSince1970: 1091), restingCollectionID: nil)

            #expect(state.selectedCollectionID == nil)
            #expect(state.searchTypeFilter.isEmpty)
            #expect(state.appChipFilter.isEmpty)
        }

        @Test("an app's own collection is where a late reopen lands")
        func whenReopenedLateInAnAppWithACollection_thenThatCollection() {
            let (state, _) = stateInACollection()
            let trigger = UUID()
            state.shelfClosedAt = Date(timeIntervalSince1970: 1000)

            state.resetShelfContextIfStale(now: Date(timeIntervalSince1970: 2000), restingCollectionID: trigger)

            #expect(state.selectedCollectionID == trigger)
        }

        @Test("closing the shelf by any path clears the app chip filter, a paste included")
        func whenShelfCloses_thenAppChipFilterCleared() {
            let (state, _) = stateInACollection()
            state.isOverlayVisible = true

            state.isOverlayVisible = false

            #expect(state.appChipFilter.isEmpty)
            #expect(state.shelfClosedAt != nil)
        }
    }
}
