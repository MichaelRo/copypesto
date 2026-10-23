// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

private struct Broken: LocalizedError {
    let errorDescription: String?
}

@Suite("Storage boot")
struct StorageBootTests {
    private func container() throws -> ModelContainer {
        try ModelContainerSetup.makeInMemory().synced
    }

    private func result(
        synced: @escaping () throws -> ModelContainer,
        local: @escaping () throws -> ModelContainer,
        cloudKitEnabled: Bool = false,
        inMemory: @escaping () throws -> ModelContainer,
        log: @escaping (String) -> Void = { _ in }
    )
        -> StorageBoot.Result
    {
        StorageBoot.run(
            openers: .init(synced: synced, syncedLocalOnly: synced, local: local, inMemory: inMemory),
            cloudKitEnabled: cloudKitEnabled, log: log
        )
    }

    @Test("an unreadable local.store does not take the clips store down with it")
    func whenLocalStoreIsBroken_thenTheClipsStoreStillOpensOnDisk() throws {
        let clips = try container()
        let boot = result(
            synced: { clips }, local: { throw Broken(errorDescription: "local.store is locked") },
            inMemory: { try container() }
        )

        #expect(boot.synced === clips)
        #expect(boot.local == nil)
        #expect(boot.isOnDisk)
    }

    @Test("every tier's failure is logged with its reason")
    func whenTiersFail_thenEachReasonIsLogged() {
        var lines: [String] = []

        let boot = result(
            synced: { throw Broken(errorDescription: "the model changed") },
            local: { try container() },
            cloudKitEnabled: true,
            inMemory: { try container() },
            log: { lines.append($0) }
        )

        #expect(!boot.isOnDisk, "the person is running on the in-memory copy")
        #expect(boot.synced != nil)
        #expect(lines.count(where: { $0.contains("the model changed") }) == 2, "\(lines)")
        #expect(lines.contains { $0.localizedCaseInsensitiveContains("in memory") }, "\(lines)")
    }

    @Test("with sync off the second disk attempt is the same as the first, so it is not repeated")
    func whenSyncIsOff_thenDiskIsTriedOnce() {
        var attempts = 0

        _ = StorageBoot.run(
            openers: .init(
                synced: { attempts += 1
                    throw Broken(errorDescription: "x")
                },
                syncedLocalOnly: { attempts += 1
                    throw Broken(errorDescription: "x")
                },
                local: { try container() }, inMemory: { try container() }
            ),
            cloudKitEnabled: false, log: { _ in }
        )

        #expect(attempts == 1)
    }

    @Test("when nothing opens, the result says so and nothing is on disk")
    func whenEverythingFails_thenNothingIsOpen() {
        let boot = result(
            synced: { throw Broken(errorDescription: "a") }, local: { throw Broken(errorDescription: "b") },
            inMemory: { throw Broken(errorDescription: "c") }
        )

        #expect(boot.synced == nil)
        #expect(!boot.isOnDisk)
    }

    @Test("a store written before schemas were versioned opens with the versioned schema and keeps its clips")
    func whenAnUnversionedStoreIsOpenedWithTheVersionedSchema_thenNothingIsLost() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = url.appendingPathComponent("clips.store")
        do {
            let old = try ModelContainer(
                for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
                configurations: ModelConfiguration("clips", url: store, cloudKitDatabase: .none)
            )
            let context = ModelContext(old)
            context.insert(ClipboardItem(
                type: .text, previewText: "kept", contentHash: "h", byteSize: 4, deviceID: "d", sequenceNumber: 1
            ))
            try context.save()
        }

        let reopened = try ModelContainerSetup.openSynced(cloudKitEnabled: false, storeURL: store)

        let items = try ModelContext(reopened).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.map(\.previewText) == ["kept"])
    }
}
