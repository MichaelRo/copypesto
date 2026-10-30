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
        try ModelContainerSetup.makeInMemory()
    }

    private func result(
        clips: @escaping () throws -> ModelContainer,
        inMemory: @escaping () throws -> ModelContainer,
        log: @escaping (String) -> Void = { _ in }
    )
        -> StorageBoot.Result
    {
        StorageBoot.run(openers: .init(clips: clips, inMemory: inMemory), log: log)
    }

    @Test("a readable clips store opens on disk and the memory copy is never made")
    func whenTheClipsStoreOpens_thenItIsOnDisk() throws {
        let clips = try container()
        var memoryOpened = false

        let boot = result(clips: { clips }, inMemory: {
            memoryOpened = true
            return try container()
        })

        #expect(boot.container === clips)
        #expect(boot.isOnDisk)
        #expect(!memoryOpened)
    }

    @Test("when the disk store fails, its reason is logged and the in-memory copy opens, said not to be on disk")
    func whenTheClipsStoreFails_thenTheReasonIsLoggedAndMemoryOpens() {
        var lines: [String] = []

        let boot = result(
            clips: { throw Broken(errorDescription: "the model changed") },
            inMemory: { try container() },
            log: { lines.append($0) }
        )

        #expect(!boot.isOnDisk, "the person is running on the in-memory copy")
        #expect(boot.container != nil)
        #expect(lines.count(where: { $0.contains("the model changed") }) == 1, "\(lines)")
        #expect(lines.contains { $0.localizedCaseInsensitiveContains("in memory") }, "\(lines)")
    }

    @Test("the disk is tried once")
    func whenTheDiskFails_thenItIsTriedOnce() {
        var attempts = 0

        _ = result(clips: {
            attempts += 1
            throw Broken(errorDescription: "x")
        }, inMemory: { try container() })

        #expect(attempts == 1)
    }

    @Test("when nothing opens, the result says so and nothing is on disk")
    func whenEverythingFails_thenNothingIsOpen() {
        let boot = result(
            clips: { throw Broken(errorDescription: "a") }, inMemory: { throw Broken(errorDescription: "c") }
        )

        #expect(boot.container == nil)
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

        let reopened = try ModelContainerSetup.openClips(storeURL: store)

        let items = try ModelContext(reopened).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.map(\.previewText) == ["kept"])
    }
}
