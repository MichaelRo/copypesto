// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import Pesto
@testable import PestoCore

extension HostedGlobals {
    @Suite("Locked collections in the app (ADR 0081)", .serialized)
    @MainActor
    struct CollectionLockIntegrationTests {
        @Test("a clip in a locked collection is not put on the pasteboard until its collection is opened")
        func writeItem_whenCollectionLockedAndClosed_writesNothing() {
            let vault = UUID()
            AppDefaults.store.set(vault.uuidString, forKey: Setting.lockedCollections.name)
            defer { AppDefaults.store.removeObject(forKey: Setting.lockedCollections.name) }
            let state = AppState()
            let item = ClipboardItem(
                type: .text, previewText: "a secret", contentHash: "h", byteSize: 8, deviceID: "d",
                sequenceNumber: 1, collectionID: vault
            )
            let before = AppPasteboard.general.changeCount

            #expect(state.isWithheldByCollectionLock(item))
            #expect(state.writeItem(item) == nil)
            #expect(AppPasteboard.general.changeCount == before)

            state.openedLockedCollections = [vault]
            #expect(!state.isWithheldByCollectionLock(item))
        }

        @Test("closing the shelf closes every opened collection")
        func close_forgetsOpenedCollections() {
            let state = AppState()
            state.isOverlayVisible = true
            state.openedLockedCollections = [UUID()]
            state.close()
            #expect(state.openedLockedCollections.isEmpty)
        }

        @Test("locking a collection needs nothing and closes it if it was open")
        func setLocked_storesTheIDAndClosesIt() async {
            let vault = UUID()
            defer { AppDefaults.store.removeObject(forKey: Setting.lockedCollections.name) }
            let state = AppState()
            state.openedLockedCollections = [vault]
            #expect(await state.setCollection(vault, locked: true))
            #expect(LockedCollections.current() == [vault])
            #expect(state.openedLockedCollections.isEmpty)
        }
    }
}
