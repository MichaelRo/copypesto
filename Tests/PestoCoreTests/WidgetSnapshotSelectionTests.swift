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

        func clips(thumbnail: (ClipboardItem) -> Data? = { _ in nil }) -> [WidgetClip] {
            WidgetSnapshotSelection.clips(from: newest(), source: { _ in "Notes" }, thumbnail: thumbnail)
        }
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
        #expect(!snapshot.clips.contains { $0.text.contains("ghp_") })
        let sealed = try SealedFileEnvelope.seal(snapshot, as: .widgetSnapshot, with: SymmetricKey(size: .bits256))
        #expect(sealed.count < WidgetSnapshotPolicy.maxFileBytes)
    }

    @Test("the fullest snapshot the bounds allow still seals under the file's bound")
    func whenEverythingIsAtItsBound_thenItStillSeals() throws {
        let worstText = String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxPreviewCharacters)
        let worstPart = String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxLinkPartCharacters)
        let perThumbnail = WidgetSnapshotPolicy.maxThumbnailTotalBytes / WidgetSnapshotPolicy.maxClips
        let clips = (0..<WidgetSnapshotPolicy.maxClips).map { _ in
            WidgetClip(
                id: UUID(), kind: .url, text: worstText, linkHost: worstPart, linkPath: worstPart, colorHex: "FFFFFF",
                source: String(repeating: "\u{1}", count: WidgetSnapshotPolicy.maxSourceCharacters), date: .now,
                isPinned: true, thumbnail: Data(repeating: 0xFF, count: perThumbnail)
            )
        }
        let snapshot = WidgetSnapshot(createdAt: .now, theme: .brand, clips: clips)

        #expect(throws: Never.self) {
            try SealedFileEnvelope.seal(snapshot, as: .widgetSnapshot, with: SymmetricKey(size: .bits256))
        }
    }
}
