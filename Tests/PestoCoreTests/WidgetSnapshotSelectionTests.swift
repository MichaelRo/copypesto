// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("What the widget snapshot may hold")
@MainActor
struct WidgetSnapshotSelectionTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private final class Clips {
        let context: ModelContext
        private var clock = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            context = try ModelContext(ModelContainerSetup.makeInMemory())
        }

        @discardableResult
        func add(_ preview: String, type: ClipboardType = .text, pinned: Bool = false) -> ClipboardItem {
            clock += 60
            let item = ClipboardItem(
                type: type, previewText: preview, contentHash: UUID().uuidString, byteSize: preview.utf8.count,
                deviceID: "t", sequenceNumber: 1
            )
            item.timestamp = clock
            item.isPinned = pinned
            context.insert(item)
            return item
        }

        func newest() -> [ClipboardItem] {
            ((try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []).sorted { $0.timestamp > $1.timestamp }
        }

        func clips(thumbnail: @escaping (ClipboardItem) -> Data? = { _ in nil }) -> [WidgetClip] {
            WidgetSnapshotSelection.clips(from: newest(), reader: .init(source: { _ in "Notes" }, thumbnail: thumbnail))
        }

        func lists(fullText: @escaping (ClipboardItem) -> String?) -> WidgetSnapshotSelection.Lists {
            let all = newest()
            return WidgetSnapshotSelection.lists(
                newest: all, pinned: all.filter(\.isPinned), reader: .init(source: { _ in nil }, fullText: fullText)
            )
        }

        @discardableResult
        func collection(_ name: String, order: Int, rules: PredicateRuleSet? = nil) throws -> Pinboard {
            let board = try Pinboard(
                name: name, symbolName: "folder", colorHex: "#2F8B4C", sortOrder: order, isSmart: rules != nil,
                smartPredicateData: rules.map(SmartCollectionPredicate.encodeRuleSet)
            )
            context.insert(board)
            return board
        }

        @discardableResult
        func add(_ preview: String, type: ClipboardType = .text, in board: Pinboard, order: Int? = nil)
        -> ClipboardItem {
            let item = add(preview, type: type)
            item.collectionID = board.id
            if let order { item.collectionOrder = order }
            return item
        }

        func snapshot(fullText: @escaping (ClipboardItem) -> String? = { _ in nil }) throws -> WidgetSnapshot {
            try WidgetSnapshotSelection.snapshot(
                in: context, now: .now, theme: .brand, reader: .init(source: { _ in nil }, fullText: fullText)
            )
        }
    }

    private func texts(_ snapshot: WidgetSnapshot, in board: Pinboard) -> [String] {
        snapshot.clips(inCollection: board.id).map(\.text)
    }

    @Test("a plain collection shows its clips in its own order, hand-placed first, and only those that may be shown")
    func whenAPlainCollectionIsCarried_thenItsOrderAndEligibilityHold() throws {
        let clips = try Clips()
        let work = try clips.collection("Work", order: 0)
        clips.add("older note", in: work)
        clips.add("placed first", in: work, order: 0)
        clips.add("masked", in: work).sensitivityRaw = SensitivityCategory.apiKey.rawValue
        clips.add("expiring", in: work).expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        clips.add("newer note", in: work)
        clips.add("not in it")

        let snapshot = try clips.snapshot()

        #expect(snapshot.collections == [WidgetCollection(
            id: work.id, name: "Work", symbolName: "folder", colorHex: "#2F8B4C"
        )])
        #expect(texts(snapshot, in: work) == ["placed first", "newer note", "older note"])
        #expect(!snapshot.allClips.contains { $0.text == "masked" || $0.text == "expiring" })
    }

    @Test("a smart collection shows the newest clips its rules match, and only those that may be shown")
    func whenASmartCollectionIsCarried_thenItsRulesChoose() throws {
        let clips = try Clips()
        let links = try clips.collection("Links", order: 0, rules: PredicateRuleSet(
            combinator: .and,
            groups: [.init(combinator: .and, rules: [PredicateRule(field: .type, op: .equals, value: .string("url"))])]
        ))
        clips.add("https://copypesto.net/a", type: .url)
        clips.add("a note")
        clips.add("https://copypesto.net/secret", type: .url).sensitivityRaw = SensitivityCategory.apiKey.rawValue
        clips.add("https://copypesto.net/b", type: .url)

        let snapshot = try clips.snapshot()

        #expect(snapshot.collection(id: links.id)?.isSmart == true)
        #expect(texts(snapshot, in: links) == ["https://copypesto.net/b", "https://copypesto.net/a"])
    }

    @Test("at most 24 collections in Pesto's order, each with at most eight clips")
    func whenThereAreManyCollections_thenTheCapsHold() throws {
        let clips = try Clips()
        let boards = try (0..<30).reversed().map { try clips.collection("c\($0)", order: $0) }
        let first = try #require(boards.last)
        for index in 0..<12 {
            clips.add("in c0 \(index)", in: first)
        }

        let snapshot = try clips.snapshot()

        #expect(snapshot.collections.map(\.name) == (0..<WidgetSnapshotPolicy.maxCollections).map { "c\($0)" })
        #expect(snapshot.clips(inCollection: first.id).count == WidgetSnapshotPolicy.maxClips)
        let pastTheCap = try #require(boards.first)
        #expect(snapshot.collection(id: pastTheCap.id) == nil)
        #expect(snapshot.clips(from: .collection(pastTheCap.id)).isEmpty)
    }

    @Test("a clip shown in Recent and in collections is carried once; Recent and Pinned keep their own lists")
    func whenAClipIsInSeveralLists_thenItIsCarriedOnce() throws {
        let clips = try Clips()
        let one = try clips.collection("One", order: 0)
        let two = try clips.collection("Two", order: 1, rules: PredicateRuleSet(
            combinator: .and,
            groups: [.init(
                combinator: .and, rules: [PredicateRule(field: .previewText, op: .contains, value: .string("both"))]
            )]
        ))
        let old = clips.add("old, in both", in: one)
        old.timestamp = Date(timeIntervalSince1970: 1)
        for index in 0..<10 {
            clips.add("filler \(index)")
        }
        let shared = clips.add("shared", in: one)

        let snapshot = try clips.snapshot()

        #expect(snapshot.clips.count == WidgetSnapshotPolicy.maxClips)
        #expect(snapshot.clips.first?.id == shared.id)
        #expect(!snapshot.clips.contains { $0.id == old.id })
        #expect(snapshot.collectionClips.map(\.text) == ["old, in both"])
        #expect(Set(snapshot.allClips.map(\.id)).count == snapshot.allClips.count)
        #expect(texts(snapshot, in: one) == ["shared", "old, in both"])
        #expect(texts(snapshot, in: two) == ["old, in both"])
        #expect(snapshot.clip(id: old.id)?.text == "old, in both")
    }

    @Test("a clip only a collection shows gets a whole text only from what Recent and Pinned left")
    func whenTheBudgetIsSpent_thenACollectionClipGetsNoWholeText() throws {
        let chunk = String(repeating: "b", count: WidgetSnapshotPolicy.maxFullTextBytes)
        let full = try Clips()
        let board = try full.collection("Old", order: 0)
        full.add("old one", in: board).timestamp = Date(timeIntervalSince1970: 1)
        for index in 0..<8 {
            full.add("chunk \(index)")
        }
        let spent = try full.snapshot { _ in chunk }
        #expect(spent.collectionClips.map(\.fullText) == [nil])
        #expect(spent.allClips.compactMap(\.fullText).reduce(0) { $0 + $1.utf8.count }
            <= WidgetSnapshotPolicy.maxFullTextTotalBytes)

        let roomy = try Clips()
        let other = try roomy.collection("Old", order: 0)
        roomy.add("old one", in: other).timestamp = Date(timeIntervalSince1970: 1)
        for index in 0..<8 {
            roomy.add("new \(index)")
        }
        #expect(try roomy.snapshot { $0.displayPreviewText }.collectionClips.map(\.fullText) == ["old one"])
    }

    private func capture(_ text: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    @Test("the newest clips that may be shown, newest first, whatever their kind, pinned ones included")
    func whenSelected_thenTheNewestComeFirst() throws {
        let clips = try Clips()
        clips.add("a pinned note", pinned: true)
        clips.add("https://copypesto.net/guide/sync?token=abc", type: .url)
        clips.add("#2F8B4C", type: .color)
        clips.add("let x = 1", type: .code)
        clips.add("photo.heic", type: .image)

        let chosen = clips.clips()

        #expect(chosen.map(\.kind) == [.image, .code, .color, .url, .text])
        #expect(chosen.last?.isPinned == true)
        let link = try #require(chosen.first { $0.kind == .url })
        #expect(link.linkHost == "copypesto.net")
        #expect(link.linkPath == "/guide/sync")
        #expect(chosen.first { $0.kind == .color }?.colorHex == "2F8B4C")
        #expect(chosen.allSatisfy { $0.source == "Notes" })
    }

    @Test("no secret, no clip still being judged, no flagged clip and no expiring clip")
    func whenAClipMustNotLeave_thenItIsNeverSelected() throws {
        let clips = try Clips()
        clips.add("kept")
        clips.add("masked").sensitivityRaw = SensitivityCategory.apiKey.rawValue
        clips.add("being judged").analysisPending = true
        clips.add("picture being judged", type: .image).analysisPending = true
        clips.add("flagged", type: .image).isNSFW = true
        clips.add("expiring").expiresAt = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(clips.clips().map(\.text) == ["kept"])
    }

    @Test("at most eight clips, each text cut to what a widget shows")
    func whenThereIsMore_thenTheBoundsHold() throws {
        let clips = try Clips()
        for index in 0..<20 {
            clips.add("copy \(index) " + String(repeating: "word ", count: 100))
        }
        clips.add("https://" + String(repeating: "l", count: 300) + ".com/path", type: .url)

        let chosen = clips.clips()

        #expect(chosen.count == WidgetSnapshotPolicy.maxClips)
        #expect(chosen[1].text.hasPrefix("copy 19 "))
        #expect(chosen.allSatisfy { $0.text.count <= WidgetSnapshotPolicy.maxPreviewCharacters })
        #expect(chosen[0].linkHost?.count == WidgetSnapshotPolicy.maxLinkPartCharacters)
    }

    @Test("a picture's thumbnail is kept only within its own bound and the snapshot's total")
    func whenThumbnailsAreLarge_thenTheBoundsHold() throws {
        let clips = try Clips()
        let oversized = clips.add("too big", type: .image)
        for index in 0..<7 {
            clips.add("picture \(index)", type: .image)
        }
        let big = Data(repeating: 1, count: WidgetSnapshotPolicy.maxThumbnailBytes)

        let chosen = clips.clips { item in
            item.id == oversized.id ? Data(count: WidgetSnapshotPolicy.maxThumbnailBytes + 1) : big
        }

        #expect(chosen.count == 8)
        #expect(chosen.last?.thumbnail == nil, "the oversized thumbnail is dropped, the clip stays")
        let total = chosen.compactMap(\.thumbnail).reduce(0) { $0 + $1.count }
        #expect(total <= WidgetSnapshotPolicy.maxThumbnailTotalBytes)
        #expect(chosen.compactMap(\.thumbnail).count == WidgetSnapshotPolicy.maxThumbnailTotalBytes / big.count)
    }

    @Test("a short text, code, link or color carries its whole text within the bounds; a picture or file never does")
    func whenATextIsShort_thenItsWholeTextIsKept() throws {
        let clips = try Clips()
        let whole = Dictionary(uniqueKeysWithValues: [
            ("long", String(repeating: "a", count: WidgetSnapshotPolicy.maxFullTextBytes + 1)),
            ("short", "the whole note, longer than its preview"), ("pic", "not text"), ("doc", "not text")
        ])
        clips.add("short")
        clips.add("long")
        clips.add("pic", type: .image)
        clips.add("doc", type: .file)

        let chosen = clips.lists { whole[$0.displayPreviewText] }.clips

        #expect(chosen.map(\.fullText) == [nil, nil, nil, "the whole note, longer than its preview"])

        let many = try Clips()
        for index in 0..<8 {
            many.add("chunk \(index)")
        }
        let chunk = String(repeating: "b", count: WidgetSnapshotPolicy.maxFullTextBytes)
        let texts = many.lists { _ in chunk }.clips.compactMap(\.fullText)
        #expect(texts.count == WidgetSnapshotPolicy.maxFullTextTotalBytes / chunk.utf8.count)
    }

    @Test(
        "pinned clips get a list of their own, the newest six that may be shown, sharing what the newest already read"
    )
    func whenPinned_thenTheyHaveTheirOwnList() throws {
        let clips = try Clips()
        for index in 0..<8 {
            clips.add("pin \(index)", pinned: true)
        }
        clips.add("hidden pin", pinned: true).sensitivityRaw = SensitivityCategory.apiKey.rawValue
        for index in 0..<8 {
            clips.add("copy \(index)")
        }
        var reads = 0

        let lists = clips.lists { item in
            reads += 1
            return item.displayPreviewText
        }

        #expect(lists.clips.map(\.text).first == "copy 7")
        #expect(lists.pinned.map(\.text) == ["pin 7", "pin 6", "pin 5", "pin 4", "pin 3", "pin 2"])
        #expect(lists.pinned.allSatisfy { $0.fullText != nil && $0.isPinned })
        #expect(reads == WidgetSnapshotPolicy.maxClips + WidgetSnapshotPolicy.maxPinned)
    }

    @Test("from a real store: a secret found by ingest stays out, the rest is sealed into a file under the bound")
    func whenReadFromAStore_thenSecretsStayOutAndItFits() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container, environment: .testing())
        try await service.ingest(capture("12 Basil Lane " + String(repeating: "x", count: 5000)))
        try await service.ingest(capture(secret))
        await service.waitForBackgroundWork()

        let snapshot = try WidgetSnapshotSelection.snapshot(
            in: ModelContext(container), now: .now, theme: .brand, source: { _ in nil }
        )

        #expect(snapshot.clips.count == 1)
        #expect(try #require(snapshot.clips.first).text.hasPrefix("12 Basil Lane"))
        #expect(snapshot.clips.first?.fullText == nil, "over the bound, it is copied by opening Pesto")
        #expect(!snapshot.clips.contains { $0.text.contains("ghp_") })
        let sealed = try SealedFileEnvelope.seal(snapshot, as: .widgetSnapshot, with: SymmetricKey(size: .bits256))
        #expect(sealed.count < WidgetSnapshotPolicy.maxFileBytes)
    }

    @Test("the fullest snapshot the bounds allow, every collection full of clips no list shares, still seals")
    func whenEverythingIsAtItsBound_thenItStillSeals() throws {
        let worstText = String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxPreviewCharacters)
        let worstPart = String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxLinkPartCharacters)
        let lists = WidgetSnapshotPolicy.maxClips + WidgetSnapshotPolicy.maxPinned
        let count = lists + WidgetSnapshotPolicy.maxCollections * WidgetSnapshotPolicy.maxClips
        let perThumbnail = WidgetSnapshotPolicy.maxThumbnailTotalBytes / count
        let wholeTexts = WidgetSnapshotPolicy.maxFullTextTotalBytes / WidgetSnapshotPolicy.maxFullTextBytes
        let all = (0..<count).map { index in
            WidgetClip(
                id: UUID(), kind: .url, text: worstText,
                fullText: index < wholeTexts ? String(
                    repeating: "\u{1}",
                    count: WidgetSnapshotPolicy.maxFullTextBytes
                ) :
                    nil,
                linkHost: worstPart, linkPath: worstPart, colorHex: "FFFFFF",
                source: String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxSourceCharacters), date: .now,
                isPinned: true, thumbnail: Data(repeating: 0xFF, count: perThumbnail)
            )
        }
        let others = Array(all.dropFirst(lists))
        let collections = (0..<WidgetSnapshotPolicy.maxCollections).map { _ in
            WidgetCollection(
                id: UUID(), name: String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxCollectionNameCharacters),
                symbolName: String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxSymbolNameCharacters),
                colorHex: "#FFFFFF", isSmart: true
            )
        }
        let members = collections.enumerated().map { index, collection in
            let start = index * WidgetSnapshotPolicy.maxClips
            return (collection.id, others[start..<start + WidgetSnapshotPolicy.maxClips].map(\.id))
        }
        let snapshot = WidgetSnapshot(
            createdAt: .now, theme: .brand, clips: Array(all.prefix(WidgetSnapshotPolicy.maxClips)),
            pinned: Array(all.prefix(lists).dropFirst(WidgetSnapshotPolicy.maxClips)), collections: collections,
            collectionClipIDs: Dictionary(uniqueKeysWithValues: members), collectionClips: others
        )

        let sealed = try SealedFileEnvelope.seal(snapshot, as: .widgetSnapshot, with: SymmetricKey(size: .bits256))
        #expect(sealed.count <= WidgetSnapshotPolicy.maxFileBytes)
    }
}
