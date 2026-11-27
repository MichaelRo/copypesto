// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("What the quick-insert set may hold")
@MainActor
struct QuickInsertSelectionTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private final class Clips {
        let context: ModelContext
        var texts: [UUID: String] = [:]
        private var clock = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            context = try ModelContext(ModelContainerSetup.makeInMemory())
        }

        @discardableResult
        func add(_ text: String, type: ClipboardType = .text, pinned: Bool = false) -> ClipboardItem {
            clock += 60
            let item = ClipboardItem(
                type: type, previewText: "", contentHash: UUID().uuidString, byteSize: text.utf8.count,
                deviceID: "t", sequenceNumber: Int64(texts.count + 1)
            )
            item.timestamp = clock
            item.isPinned = pinned
            context.insert(item)
            texts[item.id] = text
            return item
        }

        func entries() -> [QuickInsertEntry] {
            let all = (try? context.fetch(FetchDescriptor<ClipboardItem>())) ?? []
            return QuickInsertSelection.entries(
                pinned: all.filter(\.isPinned).sorted { $0.timestamp > $1.timestamp },
                recent: all.filter { !$0.isPinned }.sorted { $0.timestamp > $1.timestamp },
                text: { self.texts[$0.id] }
            )
        }
    }

    private func capture(_ text: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    @Test("pinned clips, then snippets, then the newest text, each newest first")
    func whenSelected_thenSectionsComeInOrder() throws {
        let clips = try Clips()
        clips.add("older pin", pinned: true)
        clips.add("Dear {{date}},\nthanks", pinned: true)
        clips.add("newer pin", pinned: true)
        clips.add("first copy")
        clips.add("https://copypesto.net", type: .url)
        clips.add("let x = 1", type: .code)
        clips.add("#2F8B4C", type: .color)

        let entries = clips.entries()

        #expect(entries.map(\.section) == [.pinned, .pinned, .snippets, .recent, .recent, .recent, .recent])
        #expect(entries.map(\.text) == [
            "newer pin", "older pin", "Dear {{date}},\nthanks", "#2F8B4C", "let x = 1", "https://copypesto.net",
            "first copy"
        ])
        #expect(entries.first { $0.section == .snippets }?.expandsOnInsert == true)
        #expect(entries.first { $0.section == .snippets }?.title == "Dear {{date}},")
        #expect(!entries.contains { $0.section != .snippets && $0.expandsOnInsert })
    }

    @Test("no secret, no clip still being judged, no covered clip, no expiring clip, no picture and no file")
    func whenAClipMustNotLeave_thenItIsNeverSelected() throws {
        let clips = try Clips()
        clips.add("kept")
        clips.add("masked", pinned: true).sensitivityRaw = SensitivityCategory.apiKey.rawValue
        clips.add("being judged").analysisPending = true
        clips.add("covered").isNSFW = true
        clips.add("expiring").expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
        clips.add("picture", type: .image)
        clips.add("/Users/me/file.pdf", type: .file)

        #expect(clips.entries().map(\.text) == ["kept"])
    }

    @Test("a snippet that reads clipboard or app stays out; interactive fill-ins and built-in tokens stay for AutoFill")
    func whenASnippetNeedsThePerson_thenOnlyPrivilegedContextIsLeftOut() throws {
        let clips = try Clips()
        clips.add("Hi {{input:Name}}", pinned: true)
        clips.add("Pasted: {{clipboard}}", pinned: true)
        clips.add("In {{app}}", pinned: true)
        clips.add("Signed {{isodate}} {{uuid}}{{cursor}}", pinned: true)

        #expect(
            clips.entries().map(\.text)
                == ["Signed {{isodate}} {{uuid}}{{cursor}}", "Hi {{input:Name}}"]
        )
    }

    @Test("at most the newest recent clips, and nothing over the total size")
    func whenThereIsMoreThanFits_thenTheBoundsHold() throws {
        let clips = try Clips()
        for index in 0..<80 {
            clips.add("copy \(index)")
        }
        let recent = clips.entries()
        #expect(recent.count == QuickInsertPolicy.maxRecent)
        #expect(recent.first?.text == "copy 79")

        let big = try Clips()
        let chunk = String(repeating: "a", count: QuickInsertPolicy.maxEntryBytes)
        for index in 0..<20 {
            big.add("\(index)" + chunk.dropFirst(2), pinned: true)
        }
        big.add(String(repeating: "b", count: QuickInsertPolicy.maxEntryBytes + 1))
        let entries = big.entries()
        #expect(entries.reduce(0) { $0 + $1.text.utf8.count } <= QuickInsertPolicy.maxTotalBytes)
        #expect(!entries.contains { $0.text.utf8.count > QuickInsertPolicy.maxEntryBytes })
        #expect(!entries.isEmpty)
    }

    @Test("from a real store: the full text is opened, and a secret found by ingest stays out")
    func whenReadFromAStore_thenTheFullTextIsUsedAndSecretsStayOut() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container, environment: .testing())
        let long = "line one\n" + String(repeating: "word ", count: 400)
        try await service.ingest(capture(long))
        try await service.ingest(capture(secret))
        await service.waitForBackgroundWork()

        let set = try QuickInsertSelection.set(in: container.mainContext, now: .now)

        #expect(set.entries.map(\.text) == [long])
        #expect(set.entries.first?.title == "line one")
    }

    @Test("a clip whose text holds a card number without a sensitivity flag stays out of AutoFill")
    func whenClipTextHasCardNumberWithoutFlag_thenExcludedFromQuickInsert() throws {
        let clips = try Clips()
        clips.add("safe snippet", pinned: true)
        clips.add("Cardholder: Jane\n4111 1111 1111 1111", pinned: true)
        clips.add("4111 1111 1111 1111")

        #expect(clips.entries().map(\.text) == ["safe snippet"])
    }

    @Test("a pinned clip belonging to a collection stays out of the standalone Pinned section")
    func whenPinnedInCollection_thenNotInPinnedSection() throws {
        let clips = try Clips()
        _ = clips.add("standalone pin", pinned: true)
        let inCollection = clips.add("collection pin", pinned: true)
        inCollection.collectionID = UUID()

        let set = try QuickInsertSelection.set(in: clips.context, now: .now, text: { clips.texts[$0.id] })
        let pinnedTexts = set.entries.filter { $0.section == .pinned }.map(\.text)

        #expect(pinnedTexts == ["standalone pin"])
    }

    @Test("a clip matched by two collections is carried only once in QuickInsertSet.entries")
    func whenClipInMultipleCollections_thenNoDuplicateEntryInSet() {
        let boardA = Pinboard(name: "A", symbolName: "folder", colorHex: "#3F7D4E", sortOrder: 0)
        let boardB = Pinboard(name: "B", symbolName: "star", colorHex: "#C99A2E", sortOrder: 1)
        let clip = ClipboardItem(
            type: .text, previewText: "shared clip", contentHash: "shared", byteSize: 11,
            deviceID: "d", sequenceNumber: 1
        )
        let lists = QuickInsertSelection.lists(
            pinned: [],
            recent: [],
            collections: [
                .init(collection: boardA, items: [clip]),
                .init(collection: boardB, items: [clip])
            ],
            text: { $0.previewText }
        )
        #expect(lists.entries.map(\.id) == [clip.id])
        #expect(lists.collections.map(\.entryIDs) == [[clip.id], [clip.id]])
    }
}
