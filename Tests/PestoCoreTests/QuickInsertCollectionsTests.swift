// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("The quick-insert set carries the collections the person chose")
@MainActor
struct QuickInsertCollectionsTests {
    @MainActor
    private final class Store {
        let context: ModelContext
        var texts: [UUID: String] = [:]
        private var clock = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            context = try ModelContext(ModelContainerSetup.makeInMemory())
        }

        @discardableResult
        func add(_ text: String, pinned: Bool = false, in board: Pinboard? = nil) -> ClipboardItem {
            clock += 60
            let item = ClipboardItem(
                type: .text, previewText: "", contentHash: UUID().uuidString, byteSize: text.utf8.count,
                deviceID: "t", sequenceNumber: Int64(texts.count + 1)
            )
            item.timestamp = clock
            item.isPinned = pinned
            item.collectionID = board?.id
            context.insert(item)
            texts[item.id] = text
            return item
        }

        func collection(_ name: String, order: Int) throws -> Pinboard {
            let board = try Pinboard(name: name, symbolName: "briefcase", colorHex: "#2F8B4C", sortOrder: order)
            context.insert(board)
            return board
        }

        func set(_ chosen: [UUID], returnsAfterInsert: Bool = true) throws -> QuickInsertSet {
            try QuickInsertSelection.set(
                in: context, now: .now, options: .init(collectionIDs: chosen, returnsAfterInsert: returnsAfterInsert),
                text: { self.texts[$0.id] }
            )
        }
    }

    @Test("each chosen collection comes in the person's order, with its clips, and an unchosen one is left out")
    func whenCollectionsAreChosen_thenTheyAreCarriedInThatOrder() throws {
        let store = try Store()
        let work = try store.collection("Work", order: 0)
        let travel = try store.collection("Travel", order: 1)
        let other = try store.collection("Other", order: 2)
        store.add("Standup at 10", in: work)
        store.add("Passport 123", in: travel)
        store.add("not chosen", in: other)

        let set = try store.set([travel.id, work.id])

        #expect(set.collections.map(\.name) == ["Travel", "Work"])
        #expect(set.collections.first?.symbolName == "briefcase")
        let byID = Dictionary(uniqueKeysWithValues: set.entries.map { ($0.id, $0.text) })
        #expect(set.collections.map { $0.entryIDs.compactMap { byID[$0] } } == [["Passport 123"], ["Standup at 10"]])
        #expect(!set.entries.contains { $0.text == "not chosen" && $0.section == .collection })
    }

    @Test("a clip already in the set is listed by the collection, not carried twice")
    func whenAClipIsAlsoRecent_thenItIsCarriedOnce() throws {
        let store = try Store()
        let work = try store.collection("Work", order: 0)
        let item = store.add("Standup at 10", in: work)

        let set = try store.set([work.id])

        #expect(set.entries.count(where: { $0.id == item.id }) == 1)
        #expect(set.collections.first?.entryIDs == [item.id])
    }

    @Test("a deleted or unknown collection is skipped, and the chosen count is bounded")
    func whenAChosenCollectionIsGone_thenItIsSkipped() throws {
        let store = try Store()
        let boards = try (0..<(QuickInsertPolicy.maxCollections + 3)).map { try store.collection("C\($0)", order: $0) }
        let set = try store.set([UUID()] + boards.map(\.id))
        #expect(set.collections.count == QuickInsertPolicy.maxCollections)
        #expect(set.collections.first?.name == "C0")
    }

    @Test("the after-insert choice travels in the set")
    func whenTheChoiceIsSet_thenTheSetCarriesIt() throws {
        let store = try Store()
        #expect(try store.set([], returnsAfterInsert: false).returnsAfterInsert == false)
        #expect(try store.set([]).returnsAfterInsert == true)
    }

    @Test("a clip that came from another device says so")
    func whenAClipArrivedBySync_thenItIsMarked() throws {
        let store = try Store()
        store.add("made here")
        store.add("from the Mac").syncOrigin = "mac-1"
        let set = try store.set([])
        #expect(set.entries.first { $0.text == "from the Mac" }?.fromAnotherDevice == true)
        #expect(set.entries.first { $0.text == "made here" }?.fromAnotherDevice == false)
    }

    @Test("a set written before collections opens with none, returning after insert, and no clip from elsewhere")
    func whenAnOlderSetIsRead_thenTheNewFieldsTakeTheirDefaults() throws {
        let old = #"{"createdAt":0,"entries":[{"id":"\#(UUID().uuidString)","section":"pinned","kind":"text","#
            + #""title":"Home","text":"12 Basil Lane","expandsOnInsert":false}]}"#
        let set = try JSONDecoder().decode(QuickInsertSet.self, from: Data(old.utf8))
        #expect(set.collections.isEmpty)
        #expect(set.returnsAfterInsert)
        #expect(set.entries.first?.fromAnotherDevice == false)
    }

    @Test("the chosen collections are stored as ids and read back in order, without repeats or broken ids")
    func whenStored_thenTheChoiceReadsBack() {
        let ids = [UUID(), UUID()]
        let stored = QuickInsertSelection.Options.stored(ids)
        #expect(QuickInsertSelection.Options(storedCollections: stored, returnsAfterInsert: true).collectionIDs == ids)
        let messy = stored + ",nonsense," + ids[0].uuidString
        #expect(QuickInsertSelection.Options(storedCollections: messy, returnsAfterInsert: false).collectionIDs == ids)
        #expect(QuickInsertSelection.Options(storedCollections: "", returnsAfterInsert: true).collectionIDs.isEmpty)
    }

    @Test("at most fifty pinned clips, however many are pinned")
    func whenManyArePinned_thenTheCapHolds() throws {
        let store = try Store()
        for index in 0..<60 {
            store.add("pin \(index)", pinned: true)
        }
        let set = try store.set([])
        #expect(set.entries.count(where: { $0.section == .pinned }) == QuickInsertPolicy.maxPinned)
    }

    @Test("a pinned snippet that asks for a value stays out, even when its collection is chosen")
    func whenASnippetNeedsThePerson_thenNoCollectionCarriesIt() throws {
        let store = try Store()
        let work = try store.collection("Work", order: 0)
        store.add("Hi {{input:Name}}", pinned: true, in: work)
        store.add("Plain note", in: work)
        let set = try store.set([work.id])
        #expect(!set.entries.contains { $0.text.contains("{{input") })
        #expect(set.collections.first?.entryIDs.count == 1)
    }

    @Test("collection-only clips share the set's size budget")
    func whenCollectionsAreLarge_thenTheBudgetHolds() throws {
        let store = try Store()
        let work = try store.collection("Work", order: 0)
        let chunk = String(repeating: "a", count: QuickInsertPolicy.maxEntryBytes - 8)
        for index in 0..<12 {
            store.add("\(index) " + chunk, in: work)
        }
        let set = try store.set([work.id])
        #expect(set.entries.reduce(0) { $0 + $1.text.utf8.count } <= QuickInsertPolicy.maxTotalBytes)
    }

    @Test("AutoFill lists each chosen collection under its name after Recent")
    func whenAutoFillGroups_thenCollectionsFollowTheSections() throws {
        let store = try Store()
        let work = try store.collection("Work", order: 0)
        store.add("Standup at 10", in: work)
        let groups = try QuickInsertMenu(set: store.set([work.id])).groups(matching: "")
        #expect(groups.map { $0.collection?.name ?? $0.section.rawValue } == ["recent", "Work"])
    }
}
