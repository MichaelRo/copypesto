// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Shortcut column on-disk migration")
struct ShortcutColumnMigrationTests {
    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/v1_0_0_store.store")
    }

    @Test("creates or verifies 1.0.0 fixture store and opens it with ModelContainerSetup")
    func whenOpeningStore_thenClipsLoad() throws {
        let fixture = Self.fixtureURL
        if !FileManager.default.fileExists(atPath: fixture.path) {
            let container = try ModelContainerSetup.openClips(storeURL: fixture)
            let context = ModelContext(container)
            let item = ClipboardItem(
                type: .text,
                previewText: "1.0.0 clip",
                contentHash: "hash-100",
                byteSize: 10,
                deviceID: "device-1",
                sequenceNumber: 1,
                isPinned: true
            )
            item.pinnedHotkeyIndex = 2
            context.insert(item)
            try context.save()
        }

        // Now open the store file in a temporary copy to test loading
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testStore = tempDir.appendingPathComponent("clips.store")
        try FileManager.default.copyItem(at: fixture, to: testStore)

        // Also copy wal and shm if they exist
        let wal = fixture.path + "-wal"
        let shm = fixture.path + "-shm"
        if FileManager.default.fileExists(atPath: wal) {
            try FileManager.default.copyItem(atPath: wal, toPath: testStore.path + "-wal")
        }
        if FileManager.default.fileExists(atPath: shm) {
            try FileManager.default.copyItem(atPath: shm, toPath: testStore.path + "-shm")
        }

        let reopened = try ModelContainerSetup.openClips(storeURL: testStore)
        let items = try ModelContext(reopened).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 1)
        #expect(items.first?.previewText == "1.0.0 clip")
        #expect(items.first?.pinnedHotkeyIndex == 2)
        #expect(items.first?.shortcutLastUsedAt == nil)
    }
}
