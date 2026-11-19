// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("The app empties the shared inbox through ingest")
struct InboxDrainTests {
    private struct Fixture {
        let directory: URL
        let inbox: SharedInbox
        let key: Curve25519.KeyAgreement.PrivateKey
        let container: ModelContainer
        let service: StorageService

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-drain-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            inbox = SharedInbox(root: directory.appendingPathComponent("Group", isDirectory: true))
            key = try InboxKeyStore(secrets: MemorySecrets()).loadOrCreate()
            try inbox.publish(InboxPublicKey(key.publicKey))
            container = try ModelContainerSetup.openClips(storeURL: directory.appendingPathComponent("clips.store"))
            service = StorageService(modelContainer: container, environment: .testing())
        }

        var drain: InboxDrain {
            InboxDrain(inbox: inbox, privateKey: key)
        }

        func items() throws -> [ClipboardItem] {
            try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        }

        func bytes(under url: URL) throws -> [Data] {
            let enumerator = try #require(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil))
            return try enumerator.compactMap { $0 as? URL }
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .map { try Data(contentsOf: $0) }
        }
    }

    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    @Test("shared text, a link and a picture become clips, the files go, and a second run adds nothing")
    func whenDrained_thenEachFileIsIngestedOnceAndRemoved() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let text = "shared from Notes \(UUID().uuidString)"
        let link = "https://example.com/recipe/\(UUID().uuidString)"
        let picture = Data("PICTURE-BYTES-\(UUID().uuidString)".utf8)
        try fixture.inbox.deposit(#require(InboxItem.text(text)))
        let linkURL = try #require(URL(string: link))
        try fixture.inbox.deposit(#require(InboxItem.link(linkURL)))
        try fixture.inbox.deposit(InboxItem(typeIdentifier: "public.png", payload: picture, createdAt: .now))

        let groupBytes = try fixture.bytes(under: fixture.inbox.root)
        for needle in [Data(text.utf8), Data(link.utf8), picture] {
            #expect(!groupBytes.contains { $0.range(of: needle) != nil }, "plaintext in the group container")
        }

        let report = await fixture.drain.run(into: fixture.service)
        await fixture.service.waitForBackgroundWork()

        #expect(report.added == 3)
        #expect(report.problems == 0)
        #expect(fixture.inbox.pendingFiles().isEmpty)
        let items = try fixture.items()
        #expect(items.count == 3)
        #expect(Set(items.map(\.type)) == [.text, .url, .image])
        #expect(items.contains { $0.displayPreviewText == link && $0.type == .url })

        let again = await fixture.drain.run(into: fixture.service)
        #expect(again == InboxDrain.Report())
        #expect(try fixture.items().count == 3)

        let everything = try fixture.bytes(under: fixture.directory)
        for needle in [Data(text.utf8), Data(link.utf8), picture] {
            #expect(!everything.contains { $0.range(of: needle) != nil }, "plaintext on disk after the drain")
        }
    }

    @Test("a shared secret is masked like a copied one")
    func whenASecretIsShared_thenItIsMasked() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.inbox.deposit(#require(InboxItem.text(secret)))

        _ = await fixture.drain.run(into: fixture.service)
        await fixture.service.waitForBackgroundWork()

        let item = try #require(try fixture.items().first)
        #expect(item.sensitivityRaw != nil)
        #expect(!item.gridPreview.contains(secret))
    }

    @Test("a file for another key, a truncated file and an oversized file are removed and counted, never ingested")
    func whenFilesDoNotOpen_thenTheyAreRemovedAndCounted() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let other = Curve25519.KeyAgreement.PrivateKey()
        try FileManager.default.createDirectory(at: fixture.inbox.directory, withIntermediateDirectories: true)
        func plant(_ data: Data) throws {
            try data.write(to: fixture.inbox.directory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(AppIdentity.inboxFileExtension))
        }
        let good = try InboxEnvelope.seal(
            #require(InboxItem.text("half a note")), to: InboxPublicKey(fixture.key.publicKey)
        )
        try plant(InboxEnvelope.seal(#require(InboxItem.text("not for you")), to: InboxPublicKey(other.publicKey)))
        try plant(good.prefix(good.count / 2))
        try plant(Data(count: InboxPolicy.maxFileBytes + 1))

        let report = await fixture.drain.run(into: fixture.service)

        #expect(report.discarded == 3)
        #expect(report.added == 0)
        #expect(fixture.inbox.pendingFiles().isEmpty)
        #expect(try fixture.items().isEmpty)
    }

    @Test("an item over the size limit of one copy is refused and removed, never ingested")
    func whenOverTheCopyLimit_thenRefusedAndRemoved() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let item = InboxItem(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data(repeating: 0x61, count: ClipSizePolicy.maxTextBytes + 1), createdAt: .now
        )
        try FileManager.default.createDirectory(at: fixture.inbox.directory, withIntermediateDirectories: true)
        let sealedOverLimit = try Self.sealUnchecked(item, to: InboxPublicKey(fixture.key.publicKey))
        try sealedOverLimit.write(to: fixture.inbox.directory.appendingPathComponent("big")
            .appendingPathExtension(AppIdentity.inboxFileExtension))

        let report = await fixture.drain.run(into: fixture.service)

        #expect(report.added == 0)
        #expect(report.problems == 1)
        #expect(fixture.inbox.pendingFiles().isEmpty)
        #expect(try fixture.items().isEmpty)
    }

    @Test("a shared picture's sourceImageURL threads into PasteboardCapture and triggers GIF upgrade")
    func whenSharedItemHasSourceImageURL_thenDrainThreadsItIntoIngest() async throws {
        let gifURL = try #require(URL(string: "https://media.giphy.com/media/shared/giphy.gif"))
        let still = Data("STILL-FRAME".utf8)
        let item = InboxItem(typeIdentifier: "public.png", payload: still, createdAt: .now, sourceImageURL: gifURL)
        let capture = InboxDrain.capture(of: item)
        #expect(capture.sourceImageURL == gifURL)

        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let gif = SeedFixtures.animatedGIFData(side: 16)
        let service = StorageService(modelContainer: fixture.container, environment: .testing {
            $0.remoteGIFFetcher = { requested in requested == gifURL ? gif : nil }
        })
        try fixture.inbox.deposit(item)

        let report = await fixture.drain.run(into: service)
        await service.waitForBackgroundWork()

        #expect(report.added == 1)
        let saved = try #require(try fixture.items().first)
        #expect(saved.mimeType == "com.compuserve.gif")
        #expect(saved.blob?.decryptedData() == gif)
    }

    /// A planted file over the text limit, which `seal` itself refuses to make.
    private static func sealUnchecked(_ item: InboxItem, to key: InboxPublicKey) throws -> Data {
        let fitting = InboxItem(typeIdentifier: item.typeIdentifier, payload: Data("x".utf8), createdAt: item.createdAt)
        _ = try InboxEnvelope.seal(fitting, to: key)
        var sender = try HPKE.Sender(
            recipientKey: Curve25519.KeyAgreement.PublicKey(rawRepresentation: key.rawRepresentation),
            ciphersuite: .Curve25519_SHA256_ChachaPoly, info: Data("pesto.inbox.v1".utf8)
        )
        let header = Data("PESTOINB".utf8) + Data([1]) + key.keyID + Data(sender.encapsulatedKey)
        return try header + Data(sender.seal(item.plaintext(), authenticating: header))
    }
}
