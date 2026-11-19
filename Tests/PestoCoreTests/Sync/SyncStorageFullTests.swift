// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Sync storage-full detection and recovery", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SyncStorageFullTests {
    let layout = SyncFolderLayout(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("pesto-sync-full-\(UUID().uuidString)")
    )
    let time = TimeBox()

    private func settle(_ sites: SyncSite...) async {
        for _ in 0..<2 {
            for site in sites {
                time.advance()
                await site.service.syncNow()
            }
        }
    }

    @Test(
        "an out-of-space write sets storageFull, leaves the outbox uncommitted, and sends once space returns",
        arguments: [
            CocoaError(.fileWriteOutOfSpace) as any Error,
            POSIXError(.ENOSPC),
            POSIXError(.EDQUOT),
            CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC)])
        ]
    )
    func whenWriteFailsOutOfSpace_thenStorageFullAndOutboxUncommitted(_ error: any Error) async throws {
        let outOfSpace = LockedFlag()
        outOfSpace.value = true
        let probe = SyncFolderService.FolderProbe(
            willWrite: { _ in if outOfSpace.value { throw error } },
            isICloud: { _ in false }
        )
        let a = try SyncSite(name: "mac-a", layout: layout, time: time, folderProbe: probe)
        let b = try SyncSite(name: "mac-b", layout: layout, time: time)
        let made = try SyncGroupManager.create(
            layout: layout, identity: a.identity, keyStore: a.keyStore, now: time.now
        )
        try b.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)

        try await a.copy("waiting clip")
        time.advance()
        await a.service.syncNow()

        #expect(a.service.status == .storageFull(isICloud: false))
        #expect(try a.item("waiting clip")?.syncDirty == true, "outbox stays uncommitted until space returns")

        outOfSpace.value = false
        await settle(a, b)

        if case .upToDate = a.service.status {} else { Issue.record("expected upToDate, got \(a.service.status)") }
        #expect(try b.texts() == ["waiting clip"])
    }

    @Test("an out-of-space blob write in an iCloud folder sets storageFull(isICloud: true)")
    func whenBlobWriteFailsInICloud_thenStorageFullICloud() async throws {
        let outOfSpace = LockedFlag()
        outOfSpace.value = true
        let probe = SyncFolderService.FolderProbe(
            writeData: { data, url in
                if outOfSpace.value, url.pathExtension == "pestoblob" { throw POSIXError(.ENOSPC) }
                try data.write(to: url, options: .atomic)
            },
            isICloud: { _ in true }
        )
        let a = try SyncSite(name: "mac-a", layout: layout, time: time, folderProbe: probe)
        let b = try SyncSite(name: "mac-b", layout: layout, time: time)
        let made = try SyncGroupManager.create(
            layout: layout, identity: a.identity, keyStore: a.keyStore, now: time.now
        )
        try b.keyStore.saveSyncKey(made.group.key, vaultID: made.group.vault.vaultID, epoch: 1)

        let big = String(repeating: "pesto ", count: 60_000)
        try await a.copy(big)
        let judging = ModelContext(a.container)
        try judging.fetch(FetchDescriptor<ClipboardItem>()).forEach { $0.analysisPending = false }
        try judging.saveOrRollback()
        time.advance()
        await a.service.syncNow()

        #expect(a.service.status == .storageFull(isICloud: true))
        #expect(try a.item(big)?.syncDirty == true)

        outOfSpace.value = false
        await settle(a, b)
        #expect(try b.texts() == [big])
    }

    @Test("an iCloud upload quota error after local writes succeed sets storageFull(isICloud: true) and recovers")
    func whenUbiquitousUploadQuotaError_thenStorageFullAndRecovers() async throws {
        let quotaFull = LockedFlag()
        quotaFull.value = true
        let probe = SyncFolderService.FolderProbe(
            uploadingError: { url in
                guard quotaFull.value, url.pathExtension == "pestohead" || url.pathExtension == "pestolog" else {
                    return nil
                }
                return CocoaError(.ubiquitousFileNotUploadedDueToQuota)
            },
            isICloud: { _ in true }
        )
        let a = try SyncSite(name: "mac-a", layout: layout, time: time, folderProbe: probe)
        _ = try SyncGroupManager.create(
            layout: layout, identity: a.identity, keyStore: a.keyStore, now: time.now
        )

        try await a.copy("local write succeeded")
        time.advance()
        await a.service.syncNow()

        #expect(a.service.status == .storageFull(isICloud: true))

        quotaFull.value = false
        time.advance()
        await a.service.syncNow()

        if case .upToDate = a.service.status {} else { Issue.record("expected upToDate, got \(a.service.status)") }
    }
}
