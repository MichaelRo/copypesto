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

    @Test("a snippet that would ask for a value or read the clipboard is left out; one Pesto fills by itself stays")
    func whenASnippetNeedsThePerson_thenItIsLeftOut() throws {
        let clips = try Clips()
        clips.add("Hi {{input:Name}}", pinned: true)
        clips.add("Pasted: {{clipboard}}", pinned: true)
        clips.add("In {{app}}", pinned: true)
        clips.add("Signed {{isodate}} {{uuid}}{{cursor}}", pinned: true)

        #expect(clips.entries().map(\.text) == ["Signed {{isodate}} {{uuid}}{{cursor}}"])
    }

    @Test("at most the newest thirty recent clips, and nothing over the total size")
    func whenThereIsMoreThanFits_thenTheBoundsHold() throws {
        let clips = try Clips()
        for index in 0..<45 {
            clips.add("copy \(index)")
        }
        let recent = clips.entries()
        #expect(recent.count == QuickInsertPolicy.maxRecent)
        #expect(recent.first?.text == "copy 44")

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
}
