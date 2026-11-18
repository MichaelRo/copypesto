// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Two clips may hold the same text once one is edited to it", .serialized)
@MainActor
struct DuplicateTextTests {
    private let container: ModelContainer
    private let service: StorageService
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func capture(_ text: String, at offset: TimeInterval) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: base.addingTimeInterval(offset), contentHash: Data(SHA256.hash(data: Data(text.utf8))).hexString
        )
    }

    private func ingest(_ text: String, at offset: TimeInterval) async throws -> UUID {
        await service.updateClock { [base] in base.addingTimeInterval(offset) }
        try await service.ingest(capture(text, at: offset))
        return try #require(clips().first { $0.blob?.decryptedText() == text }).id
    }

    private func clips() throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func clip(_ id: UUID) throws -> ClipboardItem {
        try #require(clips().first { $0.id == id })
    }

    /// Two clips holding "shared words": the edited one is `edited`, the other `other`; `editedIsNewer` decides which
    /// of the two was used last.
    private func twins(editedIsNewer: Bool) async throws -> (edited: UUID, other: UUID) {
        let older = try await ingest(editedIsNewer ? "shared words" : "draft words", at: 0)
        let newer = try await ingest(editedIsNewer ? "draft words" : "shared words", at: 100)
        let edited = editedIsNewer ? newer : older
        #expect(try await service.updateText(id: edited, text: "shared words") == .saved)
        return (edited, editedIsNewer ? older : newer)
    }

    @Test(
        "a fresh copy of a text two clips hold brings only the one used most recently to the front",
        arguments: [true, false]
    )
    func whenTextHeldTwiceIsCopied_thenTheMostRecentlyUsedComesForward(editedIsNewer: Bool) async throws {
        let (edited, other) = try await twins(editedIsNewer: editedIsNewer)
        let recent = editedIsNewer ? edited : other
        let stale = editedIsNewer ? other : edited
        let staleTimestamp = try clip(stale).timestamp

        await service.updateClock { [base] in base.addingTimeInterval(1000) }
        try await service.ingest(capture("shared words", at: 1000))

        #expect(try clips().count == 2)
        #expect(try clip(recent).timestamp == base.addingTimeInterval(1000))
        #expect(try clip(stale).timestamp == staleTimestamp)
    }

    @Test("a backup of two clips with one text restores both, under their own ids")
    func whenBackupHoldsTwoClipsWithOneText_thenBothAreRestored() async throws {
        let (edited, other) = try await twins(editedIsNewer: false)
        let export = try await service.backupRecords(includeSensitive: false)
        let key = BackupKey.generate()
        let file = try BackupFile.write(
            records: export.records, origin: BackupOrigin(sequence: 1, deviceID: "test", createdAt: base),
            key: key, passphrase: "correct horse battery staple", iterations: 1000
        )
        let target = try ModelContainerSetup.makeInMemory()
        let restoring = StorageService(modelContainer: target)

        let summary = try await restoring.restore(BackupFile.read(file, credential: .recoveryKey(key)))

        let restored = try ModelContext(target).fetch(FetchDescriptor<ClipboardItem>())
        #expect(summary.restored == 2)
        #expect(Set(restored.map(\.id)) == [edited, other])
        #expect(restored.allSatisfy { $0.blob?.decryptedText() == "shared words" })

        let again = try await restoring.restore(BackupFile.read(file, credential: .recoveryKey(key)))
        #expect(again.restored == 0)
        #expect(try ModelContext(target).fetchCount(FetchDescriptor<ClipboardItem>()) == 2)
    }

    @Test("a snippet made from a text two clips hold pins the one used most recently")
    func whenSnippetAddedForATextHeldTwice_thenTheMostRecentlyUsedIsPinned() async throws {
        let (edited, other) = try await twins(editedIsNewer: true)
        await service.updateClock { [base] in base.addingTimeInterval(1000) }

        let pinned = try await service.addSnippet("shared words")

        #expect(pinned == edited)
        #expect(try clip(edited).isPinned)
        #expect(try !clip(other).isPinned)
    }
}
