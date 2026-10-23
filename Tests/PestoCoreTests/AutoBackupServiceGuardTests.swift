// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

extension AutoBackupServiceTests {
    private func corruptFirstClip() throws -> UUID {
        let context = ModelContext(container)
        let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
            .first)
        item.blob?.encryptedData = Data(repeating: 7, count: 64)
        try context.save()
        return item.id
    }

    private func deleteOldestClips(_ count: Int) async throws {
        let context = ModelContext(container)
        let ids = try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
            .prefix(count).map(\.id)
        try await StorageService(modelContainer: container).deleteItems(ids: Array(ids), reason: .retention)
    }

    @Test("a clip that cannot be read is named, so it can be found and removed")
    func whenAClipCannotBeRead_thenItsIDIsReported() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        for number in 1...3 {
            try await ingest("clip \(number)")
        }
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        let bad = try corruptFirstClip()

        let outcome = await service.backUpNow()

        #expect(outcome == .refused(.unreadableClips(1)))
        #expect(service.unreadableClipIDs == [bad])
        service.stop()
    }

    @Test("deleting the unreadable clips lets the next backup through, and leaves no tombstone behind")
    func whenUnreadableClipsAreDeleted_thenBackupResumesWithoutATombstone() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        for number in 1...3 {
            try await ingest("clip \(number)")
        }
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)
        _ = try corruptFirstClip()
        _ = await service.backUpNow()

        let removed = await service.deleteUnreadableClips()

        #expect(removed == 1)
        #expect(service.unreadableClipIDs.isEmpty)
        guard case .written = await service.backUpNow() else {
            Issue.record("the backup did not resume")
            return
        }
        let tombstones = try ModelContext(container).fetchCount(FetchDescriptor<DeletedItemTombstone>())
        #expect(tombstones == 0)
        service.stop()
    }

    @Test("a history that loses a little each time is refused once it is under half of its largest backup")
    func whenHistoryShrinksGradually_thenTheBackupIsRefusedAtHalf() async throws {
        let (service, defaults) = try service()
        defer { clean(defaults) }
        for number in 1...12 {
            try await ingest("clip \(number)")
        }
        _ = try await service.enable(passphrase: nil, folder: folder, includeSensitive: false, iterations: 1000)

        for removed in [3, 2, 1] {
            try await deleteOldestClips(removed)
            guard case .written = await service.backUpNow() else {
                Issue.record("a small change was refused")
                return
            }
        }

        try await deleteOldestClips(1)
        #expect(await service.backUpNow() == .refused(.muchSmaller(now: 5, before: 12)))
        service.stop()
    }
}
