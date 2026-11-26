// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("The quick-insert set and widget snapshot fit their files whatever the text holds")
@MainActor
struct QuickInsertEncodedSizeTests {
    private static let control = "\u{1}"
    /// One character of about 40 KB: a character count alone does not bound it.
    private static let hugeCharacter = "e" + String(repeating: "\u{301}", count: 20_000)

    private final class Clips {
        let context: ModelContext
        var texts: [UUID: String] = [:]
        private var clock = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            context = try ModelContext(ModelContainerSetup.makeInMemory())
        }

        func add(_ text: String, title: String, pinned: Bool = false) -> ClipboardItem {
            clock += 60
            let item = ClipboardItem(
                type: .url, previewText: title, contentHash: UUID().uuidString, byteSize: text.utf8.count,
                deviceID: "t", sequenceNumber: Int64(texts.count + 1)
            )
            item.timestamp = clock
            item.isPinned = pinned
            context.insert(item)
            item.updateMetadata {
                $0.customTitle = title
                $0.ogTitle = title
            }
            texts[item.id] = text
            return item
        }

        func collection(_ name: String, order: Int) throws -> Pinboard {
            let board = Pinboard(name: name, symbolName: name, colorHex: "#2F8B4C", sortOrder: order)
            context.insert(board)
            return board
        }
    }

    /// Every list at its count bound, each clip with `title` as its titles and source and a body of `body`.
    private func fullestSet(
        title: String, snippetBody: String, body: String
    ) throws
        -> QuickInsertSet
    {
        let clips = try Clips()
        let pinned = (0..<QuickInsertPolicy.maxPinned).map { clips.add("\($0)" + body, title: title, pinned: true) }
        let snippets = (0..<QuickInsertPolicy.maxSnippets).map {
            clips.add("\($0){{input:Name}}" + snippetBody, title: title, pinned: true)
        }
        let recent = (0..<QuickInsertPolicy.maxRecent).map { clips.add("\($0)" + body, title: title) }
        let collections = try (0..<QuickInsertPolicy.maxCollections).map { order in
            let board = try clips.collection(title, order: order)
            let members = (0..<QuickInsertPolicy.maxCollectionClips).map { clips.add("\($0)" + body, title: title) }
            return QuickInsertSelection.Members(collection: board, items: members)
        }
        let lists = QuickInsertSelection.lists(
            pinned: pinned + snippets, recent: recent, collections: collections,
            reader: QuickInsertSelection.Reader(
                text: { clips.texts[$0.id] },
                source: { _ in (title, false) },
                fieldMemory: { _ in ["Name": String(repeating: Self.control, count: 100)] }
            )
        )
        return QuickInsertSet(createdAt: .now, entries: lists.entries, collections: lists.collections)
    }

    private func sealedBytes(_ set: QuickInsertSet) throws -> Int {
        try QuickInsertEnvelope.seal(set, with: SymmetricKey(size: .bits256)).count
    }

    private func encodedBytes(_ text: String) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(text).count - 2
    }

    @Test("every clip at its count bound, with control-character text, titles and sources, seals")
    func whenEveryListIsFullOfControlCharacters_thenTheSetSeals() throws {
        let long = String(repeating: Self.control, count: QuickInsertPolicy.maxTitleCharacters)
        let count = QuickInsertPolicy.maxPinned + QuickInsertPolicy.maxSnippets + QuickInsertPolicy.maxRecent
            + QuickInsertPolicy.maxCollections * QuickInsertPolicy.maxCollectionClips
        let share = QuickInsertPolicy.maxTotalBytes / count / 6 - 24
        let body = String(repeating: Self.control, count: share)

        let set = try fullestSet(title: long, snippetBody: body, body: body)

        #expect(set.entries.count == count)
        #expect(try sealedBytes(set) <= QuickInsertPolicy.maxFileBytes)
    }

    @Test("bodies that would fill the budget as raw bytes are charged what they encode to")
    func whenBodiesNeedEscaping_thenTheBudgetCountsTheEncodedBytes() throws {
        let long = String(repeating: Self.control, count: QuickInsertPolicy.maxTitleCharacters)
        let body = String(repeating: Self.control, count: 480)

        let set = try fullestSet(title: long, snippetBody: body, body: body)
        let charged = try set.entries.reduce(0) { total, entry in
            let memory = try (entry.fieldMemory ?? [:]).reduce(0) {
                try $0 + encodedBytes($1.key) + encodedBytes($1.value)
            }
            return try total + encodedBytes(entry.text) + memory
        }

        #expect(set.entries.contains { $0.fieldMemory != nil })
        #expect(charged <= QuickInsertPolicy.maxTotalBytes)
        #expect(try sealedBytes(set) <= QuickInsertPolicy.maxFileBytes)
    }

    @Test("titles, sources and collection names are bounded in bytes, not only in characters")
    func whenACharacterIsHuge_thenTheSetStillSeals() throws {
        let set = try fullestSet(title: Self.hugeCharacter, snippetBody: "a", body: "a")

        #expect(!set.entries.isEmpty)
        #expect(set.entries.allSatisfy { !$0.title.isEmpty })
        #expect(try sealedBytes(set) <= QuickInsertPolicy.maxFileBytes)
    }

    @Test("a string costs what JSONEncoder writes for it, for every ASCII scalar and beyond")
    func whenCosted_thenItMatchesTheEncoder() throws {
        let scalars = (0...0x7F).compactMap { UnicodeScalar($0) } + ["é", "\u{2028}", "\u{2029}", "\u{85}", "🌿"]
        for scalar in scalars {
            let text = String(Character(scalar))
            #expect(try EncodedText.bytes(text) == encodedBytes(text), "U+\(String(scalar.value, radix: 16))")
        }
        #expect(try EncodedText.bytes("a/b\r\n\"c\"") == encodedBytes("a/b\r\n\"c\""))
    }

    @Test("a cut keeps whole characters within four bytes for each allowed character")
    func whenCut_thenCharactersAndBytesAreBounded() {
        #expect(EncodedText.prefix("abcdef", maxCharacters: 4) == "abcd")
        #expect(EncodedText.prefix("🌿🌿🌿", maxCharacters: 3) == "🌿🌿🌿")
        #expect(EncodedText.prefix(String(repeating: Self.control, count: 6), maxCharacters: 3) == "\u{1}\u{1}")
        #expect(EncodedText.prefix("a" + Self.hugeCharacter + "b", maxCharacters: 10) == "a")
        #expect(EncodedText.prefix(Self.hugeCharacter, maxCharacters: 10).isEmpty)
    }

    @Test("an ordinary title of the longest characters keeps its whole length")
    func whenATitleIsOrdinary_thenItIsNotCutShort() throws {
        let title = String(repeating: "🌿", count: QuickInsertPolicy.maxTitleCharacters)
        let clips = try Clips()
        let item = clips.add("body", title: title)

        let entries = QuickInsertSelection.entries(pinned: [], recent: [item], text: { clips.texts[$0.id] })

        #expect(entries.first?.title == title)
        #expect(entries.first?.customTitle == title)
        #expect(entries.first?.ogTitle == title)
    }

    @Test("a widget snapshot of clips and collections made of huge characters seals")
    func whenAWidgetCharacterIsHuge_thenTheSnapshotStillSeals() throws {
        let clips = try Clips()
        let collections = try (0..<WidgetSnapshotPolicy.maxCollections).map { order in
            let board = try clips.collection(Self.hugeCharacter, order: order)
            let members = (0..<WidgetSnapshotPolicy.maxClips).map { _ in
                let item = clips.add("a", title: Self.hugeCharacter)
                item.collectionID = board.id
                return item
            }
            return (board, members)
        }
        try clips.context.save()

        let snapshot = try WidgetSnapshotSelection.snapshot(
            in: clips.context, now: .now, theme: .brand,
            reader: WidgetSnapshotSelection.Reader(source: { _ in Self.hugeCharacter })
        )
        let sealed = try SealedFileEnvelope.seal(snapshot, as: .widgetSnapshot, with: SymmetricKey(size: .bits256))

        #expect(snapshot.collections.count == collections.count)
        #expect(!snapshot.collectionClips.isEmpty)
        #expect(sealed.count <= WidgetSnapshotPolicy.maxFileBytes)
    }
}
