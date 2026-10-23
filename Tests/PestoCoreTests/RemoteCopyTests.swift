// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Copies from another device")
struct RemoteCopyTests {
    private let container: ModelContainer
    private let service: StorageService

    init() async throws {
        container = try ModelContainerSetup.makeInMemory().synced
        service = StorageService(modelContainer: container)
    }

    private func capture(isRemote: Bool, hash: String = UUID().uuidString) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data("https://example.com/from-phone".utf8),
            payloadString: "https://example.com/from-phone",
            frontmostBundleID: "com.apple.finder",
            contentHash: hash,
            isRemote: isRemote
        )
    }

    private func onlyItem() throws -> ClipboardItem {
        try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
    }

    @Test("a copy that arrived from an iPhone is not attributed to whichever Mac app is in front")
    func ingest_remoteCopy_hasNoMacSourceApp() async throws {
        try await service.ingest(capture(isRemote: true))

        let item = try onlyItem()

        #expect(item.isRemote)
        #expect(item.sourceBundleID == nil, "the frontmost Mac app did not make this copy")
        #expect(item.sourceAppName == "Another device")
    }

    @Test("a local copy is still attributed to the app in front")
    func ingest_localCopy_keepsSourceApp() async throws {
        try await service.ingest(capture(isRemote: false))

        #expect(try onlyItem().sourceBundleID == "com.apple.finder")
    }

    @Test("copying a clip again from another device marks the existing clip as remote")
    func ingest_remoteRecopyOfALocalClip_marksItRemote() async throws {
        let hash = UUID().uuidString
        await service.updateClock { Date(timeIntervalSince1970: 1_800_000_000) }
        try await service.ingest(capture(isRemote: false, hash: hash))
        await service.updateClock { Date(timeIntervalSince1970: 1_800_000_100) }

        try await service.ingest(capture(isRemote: true, hash: hash))

        let item = try onlyItem()
        #expect(item.isRemote)
        #expect(item.sourceBundleID == nil)
        #expect(item.sourceAppName == "Another device")
    }

    @Test("copying a remote clip again on this Mac attributes it to the app in front and clears the remote mark")
    func ingest_localRecopyOfARemoteClip_clearsTheRemoteMark() async throws {
        let hash = UUID().uuidString
        await service.updateClock { Date(timeIntervalSince1970: 1_800_000_000) }
        try await service.ingest(capture(isRemote: true, hash: hash))
        await service.updateClock { Date(timeIntervalSince1970: 1_800_000_100) }

        try await service.ingest(capture(isRemote: false, hash: hash))

        let item = try onlyItem()
        #expect(!item.isRemote)
        #expect(item.sourceBundleID == "com.apple.finder")
    }
}

@Suite("Copies from another device: backup", .serialized)
struct RemoteCopyBackupTests {
    @Test("a restored clip from another device is still marked remote and has no Mac source app")
    func restore_remoteClip_staysRemote() async throws {
        let source = try ModelContainerSetup.makeInMemory().synced
        let target = try ModelContainerSetup.makeInMemory().synced
        let sourceService = StorageService(modelContainer: source)
        let targetService = StorageService(modelContainer: target)
        let payload = Data("https://example.com/from-phone".utf8)
        try await sourceService.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: "https://example.com/from-phone",
            frontmostBundleID: "com.apple.finder", contentHash: UUID().uuidString, isRemote: true
        ))

        let export = try await sourceService.backupRecords(includeSensitive: true)
        let key = BackupKey.generate()
        let file = try BackupFile.write(
            records: export.records, origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: .now),
            key: key, passphrase: "correct horse battery staple", iterations: 1000
        )
        _ = try await targetService.restore(BackupFile.read(file, credential: .recoveryKey(key)))

        let restored = try #require(try ModelContext(target).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(restored.isRemote)
        #expect(restored.sourceBundleID == nil)
        #expect(restored.sourceAppName == "Another device")
    }

    @Test("a backup made before the remote mark existed still reads, as a local clip")
    func decode_oldMetadata_isLocal() throws {
        let metadata = BackupItemMetadata(
            id: UUID(), timestamp: .now, typeRaw: "text", mimeType: "public.utf8-plain-text", plainHash: "x"
        )
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        json["isRemote"] = nil

        let decoded = try JSONDecoder().decode(
            BackupItemMetadata.self, from: JSONSerialization.data(withJSONObject: json)
        )

        #expect(decoded.isRemote != true)
    }
}
