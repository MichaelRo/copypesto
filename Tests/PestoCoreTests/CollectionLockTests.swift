// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Locked collections (ADR 0081)")
struct CollectionLockTests {
    private let vault = UUID()
    private let open = UUID()

    // MARK: - The policy

    @Test("a locked collection's clips are admitted only inside that collection, once it is opened")
    func whenLocked_thenOnlyInsideTheOpenedCollection() {
        let closed = CollectionLock(locked: [vault])
        #expect(!closed.admits(collectionID: vault, in: nil))
        #expect(!closed.admits(collectionID: vault, in: vault))
        let opened = CollectionLock(locked: [vault], opened: [vault])
        #expect(opened.admits(collectionID: vault, in: vault))
        #expect(!opened.admits(collectionID: vault, in: nil))
        #expect(!opened.admits(collectionID: vault, in: open))
    }

    @Test("a clip in no collection or an unlocked one is admitted everywhere")
    func whenNotLocked_thenAdmitted() {
        let lock = CollectionLock(locked: [vault])
        #expect(lock.admits(collectionID: nil, in: nil))
        #expect(lock.admits(collectionID: open, in: nil))
        #expect(lock.admits(collectionID: open, in: open))
    }

    @Test("outside Pesto a locked collection's clips are never offered, opened or not")
    func whenOutside_thenNeverOffered() {
        let opened = CollectionLock(locked: [vault], opened: [vault])
        #expect(opened.hidesOutside(collectionID: vault))
        #expect(!opened.hidesOutside(collectionID: open))
        #expect(!opened.hidesOutside(collectionID: nil))
    }

    @Test("opening a collection that is not locked opens nothing")
    func whenOpeningUnlocked_thenNothingOpens() {
        var lock = CollectionLock(locked: [vault])
        lock.open(open)
        #expect(lock.opened.isEmpty)
        lock.open(vault)
        #expect(lock.opened == [vault])
        lock.closeAll()
        #expect(lock.opened.isEmpty)
    }

    @Test("the stored list reads ids joined by commas, drops what is not an id, and toggles one")
    func whenStored_thenRoundTrips() {
        let stored = LockedCollections.encode([vault, open])
        #expect(LockedCollections.ids(from: stored) == [vault, open])
        #expect(LockedCollections.ids(from: " \(vault.uuidString) , junk,") == [vault])
        #expect(LockedCollections.ids(from: LockedCollections.toggle(vault, in: stored)) == [open])
    }

    @Test("the lock is a setting of this device, off for every collection until it is set")
    func whenNeverSet_thenNothingIsLocked() {
        let store = ThrowawayDefaults.make()
        #expect(LockedCollections.current(from: store).isEmpty)
        store.set(vault.uuidString, forKey: Setting.lockedCollections.name)
        #expect(LockedCollections.current(from: store) == [vault])
        #expect(Setting.allNames.contains(Setting.lockedCollections.name))
    }

    @Test("with the History Lock on, widgets, AutoFill and the keyboard stay empty unless the person says otherwise")
    func whenNeverSet_thenClipsDoNotShowOutsideWhileLocked() {
        #expect(Setting.showsClipsOutsideWhileLocked.defaultValue == false)
    }

    // MARK: - The history index

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            container = try ModelContainerSetup.makeInMemory()
            context = ModelContext(container)
        }

        @discardableResult
        func add(_ text: String, at seconds: Double, collection: UUID? = nil, pinned: Bool = false) throws
            -> ClipboardItem
        {
            let item = ClipboardItem(
                type: .text, previewText: text, contentHash: UUID().uuidString, byteSize: text.utf8.count,
                deviceID: "t", sequenceNumber: Int64(seconds), collectionID: collection
            )
            item.timestamp = Date(timeIntervalSince1970: seconds)
            item.isPinned = pinned
            context.insert(item)
            try context.save()
            return item
        }

        func items() throws -> [ClipboardItem] {
            try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))
        }
    }

    @Test("All, search and a smart collection leave out a locked collection's clips")
    func whenLocked_thenTheIndexLeavesThemOut() throws {
        let fixture = try Fixture()
        let free = try fixture.add("salad recipe", at: 1)
        let hidden = try fixture.add("salad secret", at: 2, collection: vault)
        let index = try HistoryIndex(items: fixture.items())
        let lock = CollectionLock(locked: [vault], opened: [vault])

        #expect(index.matching(HistoryCriteria(collectionLock: lock)) == [free.id])
        #expect(index.matching(HistoryCriteria(query: "salad", collectionLock: lock)) == [free.id])
        #expect(index.matching(HistoryCriteria(collectionLock: lock), smartCollection: { _ in true }) == [free.id])
        #expect(index.matching(HistoryCriteria(collectionID: vault, collectionLock: lock)) == [hidden.id])
    }

    @Test("a locked collection that is not opened shows nothing, even on its own chip")
    func whenNotOpened_thenItsChipIsEmpty() throws {
        let fixture = try Fixture()
        try fixture.add("secret", at: 1, collection: vault)
        let index = try HistoryIndex(items: fixture.items())
        let lock = CollectionLock(locked: [vault])
        #expect(index.matching(HistoryCriteria(collectionID: vault, collectionLock: lock)).isEmpty)
    }

    // MARK: - Outside Pesto

    @Test("Shortcuts, AppleScript, AutoFill and widgets never offer a locked collection's clip")
    func whenLocked_thenNotOfferedOutside() throws {
        let fixture = try Fixture()
        let free = try fixture.add("free", at: 1)
        let hidden = try fixture.add("hidden", at: 2, collection: vault)
        #expect(ShortcutClipSearch.isOffered(free, nsfwMode: .blur, locked: [vault]))
        #expect(!ShortcutClipSearch.isOffered(hidden, nsfwMode: .blur, locked: [vault]))
        #expect(!ShortcutClipSearch.isOfferedOutsidePesto(hidden, locked: [vault]))
        #expect(!ShortcutClipSearch.matches(hidden, query: "hid", locked: [vault]))
        let found = try ShortcutClipSearch.search("", in: fixture.context, nsfwMode: .blur, locked: [vault])
        #expect(found.map(\.id) == [free.id])
        let byID = try ShortcutClipSearch.clips(
            ids: [hidden.id, free.id], in: fixture.context, nsfwMode: .blur, locked: [vault]
        )
        #expect(byID.map(\.id) == [free.id])
    }

    @Test("the widget snapshot holds no clip and no chip of a locked collection")
    func whenLocked_thenTheWidgetLeavesItOut() throws {
        let fixture = try Fixture()
        let board = Pinboard(id: vault, name: "Vault", symbolName: "lock", colorHex: "#2F8B4C", sortOrder: 0)
        fixture.context.insert(board)
        let free = try fixture.add("free", at: 1)
        try fixture.add("hidden", at: 2, collection: vault)
        try fixture.add("hidden pin", at: 3, collection: vault, pinned: true)
        let snapshot = try WidgetSnapshotSelection.snapshot(
            in: fixture.context, now: .now, theme: .brand, reader: .init(source: { _ in nil }),
            lockedCollections: [vault]
        )
        #expect(snapshot.clips.map(\.id) == [free.id])
        #expect(snapshot.collections.isEmpty)
    }

    @Test("the keyboard and AutoFill set holds no clip and no chip of a locked collection")
    func whenLocked_thenTheQuickInsertSetLeavesItOut() throws {
        let fixture = try Fixture()
        let board = Pinboard(id: vault, name: "Vault", symbolName: "lock", colorHex: "#2F8B4C", sortOrder: 0)
        fixture.context.insert(board)
        let free = try fixture.add("free", at: 1)
        try fixture.add("hidden", at: 2, collection: vault)
        let set = try QuickInsertSelection.set(
            in: fixture.context, now: .now,
            options: .init(collectionMode: .all, lockedCollectionIDs: [vault]),
            text: { $0.displayPreviewText }
        )
        #expect(set.entries.map(\.id) == [free.id])
        #expect(set.collections.isEmpty)
    }
}
