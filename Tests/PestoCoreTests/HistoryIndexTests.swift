// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("History index")
struct HistoryIndexTests {
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            container = try ModelContainerSetup.makeInMemory().synced
            context = ModelContext(container)
        }

        @discardableResult
        func add(
            _ text: String, type: ClipboardType = .text, at seconds: Double, source: String? = nil,
            title: String? = nil, note: String? = nil, tags: [String] = [], language: String? = nil,
            nsfw: Bool = false, remote: Bool = false, collection: UUID? = nil, masked: String? = nil,
            sensitivity: SensitivityCategory? = nil
        )
        throws -> ClipboardItem {
            let item = ClipboardItem(
                type: type, sourceBundleID: source, previewText: text,
                sensitivity: sensitivity, sensitivityMaskedPreview: masked,
                contentHash: UUID().uuidString, byteSize: text.utf8.count, deviceID: "t",
                sequenceNumber: Int64(seconds), collectionID: collection
            )
            item.timestamp = Date(timeIntervalSince1970: seconds)
            item.detectedLanguage = language
            item.isNSFW = nsfw
            item.isRemote = remote
            context.insert(item)
            if title != nil || note != nil || !tags.isEmpty {
                item.updateMetadata {
                    $0.customTitle = title
                    $0.userNote = note
                    $0.tags = tags
                }
            }
            try context.save()
            return item
        }

        func items() throws -> [ClipboardItem] {
            try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))
        }
    }

    @Test("rows come newest first")
    func whenBuilt_thenNewestFirst() throws {
        let fixture = try Fixture()
        let old = try fixture.add("old", at: 1)
        let new = try fixture.add("new", at: 2)
        let index = try HistoryIndex(items: fixture.items())
        #expect(index.matching(HistoryCriteria()) == [new.id, old.id])
    }

    @Test("typed text matches the preview, the title, the note and the tags, folded for case and accents")
    func whenQuery_thenAnyFieldMatches() throws {
        let fixture = try Fixture()
        let preview = try fixture.add("Café menu for Friday", at: 1)
        let title = try fixture.add("x", at: 2, title: "Quarterly Report")
        let note = try fixture.add("y", at: 3, note: "ask Maria about the invoice")
        let tag = try fixture.add("z", at: 4, tags: ["invoice-2026"])
        _ = try fixture.add("nothing here", at: 5)
        let index = try HistoryIndex(items: fixture.items())

        #expect(index.matching(HistoryCriteria(query: "cafe")) == [preview.id])
        #expect(index.matching(HistoryCriteria(query: "REPORT")) == [title.id])
        #expect(index.matching(HistoryCriteria(query: "maria")) == [note.id])
        #expect(index.matching(HistoryCriteria(query: "invoice")) == [tag.id, note.id])
    }

    @Test("a query cannot match across two fields")
    func whenQuerySpansFields_thenNoMatch() throws {
        let fixture = try Fixture()
        _ = try fixture.add("alpha", at: 1, title: "beta")
        let index = try HistoryIndex(items: fixture.items())
        #expect(index.matching(HistoryCriteria(query: "alphabeta")).isEmpty)
        #expect(index.matching(HistoryCriteria(query: "alpha\u{1}beta")).isEmpty)
    }

    @Test("a hidden secret is searched by its mask, never by its text")
    func whenSecret_thenMaskIsSearched() throws {
        let fixture = try Fixture()
        _ = try fixture.add("sk-live-123456789", at: 1, masked: "••••", sensitivity: .apiKey)
        let index = try HistoryIndex(items: fixture.items())
        #expect(index.matching(HistoryCriteria(query: "123456789")).isEmpty)
        #expect(index.matching(HistoryCriteria(query: "api key")).count == 1)
    }

    @Test("@prefix matches a tag by prefix or the language exactly")
    func whenAtQuery_thenTagOrLanguage() throws {
        let fixture = try Fixture()
        let tagged = try fixture.add("a", at: 1, tags: ["Python-notes"])
        let language = try fixture.add("b", at: 2, language: "python")
        _ = try fixture.add("c", at: 3, language: "pythonic")
        let index = try HistoryIndex(items: fixture.items())
        #expect(Set(index.matching(HistoryCriteria(query: "@python"))) == [tagged.id, language.id])
    }

    @Test("scope and chips filter like ShelfFilter does")
    func whenCriteria_thenFiltered() throws {
        let fixture = try Fixture()
        let collection = UUID()
        let a = try fixture.add("one", at: 1, source: "com.a", collection: collection)
        let b = try fixture.add("two", type: .url, at: 2, source: "com.b", nsfw: true)
        let c = try fixture.add("three", at: 3, source: "com.a", remote: true)
        let index = try HistoryIndex(items: fixture.items())

        #expect(index.matching(HistoryCriteria(hidesSensitive: true)) == [c.id, a.id])
        #expect(index.matching(HistoryCriteria(appBundleIDs: ["com.a"])) == [c.id, a.id])
        #expect(index.matching(HistoryCriteria(collectionID: collection)) == [a.id])
        #expect(index.matching(HistoryCriteria(searchActive: true, types: [ClipboardType.url.rawValue])) == [b.id])
        #expect(index.matching(HistoryCriteria(searchActive: true, sources: ["com.b"])) == [b.id])
        #expect(index.matching(HistoryCriteria(searchActive: true, dateCutoff: Date(timeIntervalSince1970: 2))) == [
            c.id,
            b.id
        ])
        #expect(index.matching(HistoryCriteria(searchActive: true, sensitiveOnly: true)) == [b.id])
        #expect(index.matching(HistoryCriteria(searchActive: true, remoteOnly: true)) == [c.id])
        #expect(
            index.matching(HistoryCriteria(types: ["nope"])).count == 3,
            "chips apply only while a search is active"
        )
    }

    @Test("a smart collection is decided by the caller, per clip")
    func whenSmartCollection_thenCallerDecides() throws {
        let fixture = try Fixture()
        let keep = try fixture.add("keep", at: 1)
        _ = try fixture.add("drop", at: 2)
        let index = try HistoryIndex(items: fixture.items())
        #expect(index.matching(HistoryCriteria(), smartCollection: { $0 == keep.id }) == [keep.id])
    }

    @Test("a saved clip is inserted at the front, a re-copied one moves, a deleted one goes")
    func whenChanges_thenIncremental() throws {
        let fixture = try Fixture()
        let first = try fixture.add("first", at: 1)
        let second = try fixture.add("second", at: 2)
        var index = try HistoryIndex(items: fixture.items())

        let third = try fixture.add("third", at: 3)
        index.apply(upserting: [third])
        #expect(index.matching(HistoryCriteria()) == [third.id, second.id, first.id])

        first.timestamp = Date(timeIntervalSince1970: 4)
        index.apply(upserting: [first])
        #expect(index.matching(HistoryCriteria()) == [first.id, third.id, second.id])

        second.customTitle = "renamed"
        index.apply(upserting: [second])
        #expect(index.matching(HistoryCriteria(query: "renamed")) == [second.id])

        index.apply(removing: [third.persistentModelID])
        #expect(index.matching(HistoryCriteria()) == [first.id, second.id])
    }

    @Test("dropping the text keeps the rows but nothing searchable, and a rebuild brings it back")
    func whenTextDropped_thenNoPlaintextRemains() throws {
        let fixture = try Fixture()
        _ = try fixture.add("secret plan", at: 1)
        var index = try HistoryIndex(items: fixture.items())
        index.dropSearchText()
        #expect(index.matching(HistoryCriteria(query: "secret")).isEmpty)
        #expect(!index.hasSearchText)
        index = try HistoryIndex(items: fixture.items())
        #expect(index.hasSearchText)
        #expect(index.matching(HistoryCriteria(query: "secret")).count == 1)
    }
}

@Suite("History save change")
struct HistorySaveChangeTests {
    private final class Collector: @unchecked Sendable {
        var changes: [HistorySaveChange] = []
    }

    @Test("a save reports the clips it inserted, updated and deleted, not the blobs or collections")
    func whenSaved_thenOnlyClipsAreReported() throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let context = ModelContext(container)
        let collector = Collector()
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) {
            if let change = HistorySaveChange(userInfo: $0.userInfo) { collector.changes.append(change) }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let item = ClipboardItem(
            type: .text, previewText: "a", contentHash: "h", byteSize: 1, deviceID: "t", sequenceNumber: 1
        )
        let blob = ClipboardBlob(encryptedData: Data([1]), nonceData: Data([2]), mimeType: "public.utf8-plain-text")
        item.blob = blob
        context.insert(item)
        context.insert(blob)
        context.insert(Pinboard(name: "Work", symbolName: "folder", colorHex: "#2F7A49", sortOrder: 0))
        try context.save()
        #expect(collector.changes.last?.inserted == [item.persistentModelID])

        item.isPinned = true
        try context.save()
        #expect(collector.changes.last?.updated == [item.persistentModelID])
        #expect(collector.changes.last?.inserted.isEmpty == true)

        let identifier = item.persistentModelID
        context.delete(item)
        try context.save()
        #expect(collector.changes.last?.deleted == [identifier])
    }

    @Test("a notification without the usual keys is not a change")
    func whenNoKeys_thenNil() {
        #expect(HistorySaveChange(userInfo: nil) == nil)
        #expect(HistorySaveChange(userInfo: ["unrelated": 1]) == nil)
    }
}
