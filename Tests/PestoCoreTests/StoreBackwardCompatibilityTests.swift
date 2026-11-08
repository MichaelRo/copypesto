// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Store fixtures from earlier releases open and accept new clips")
struct StoreBackwardCompatibilityTests {
    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    private func copyFixture(_ name: String, into directory: URL) throws -> URL {
        let source = Self.fixtureURL(name)
        let target = directory.appendingPathComponent("clips.store")
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: source.path + suffix) {
            try FileManager.default.copyItem(atPath: source.path + suffix, toPath: target.path + suffix)
        }
        return target
    }

    @Test(
        "every shipped store fixture opens through StorageBoot and can ingest a new clip",
        arguments: [
            ("v1_0_0_store.store", 1, "1.0.0 clip"),
            ("v1_1_0_store.store", 3, "1.1.0 clip 1")
        ]
    )
    func whenShippedFixtureIsOpened_thenHistorySurvivesAndNewClipsIngest(
        fixtureName: String,
        expectedCount: Int,
        expectedFirstPreview: String
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-compat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = try copyFixture(fixtureName, into: tempDir)
        let boot = StorageBoot.run(
            openers: .init(
                clips: { try ModelContainerSetup.openClips(storeURL: storeURL) },
                inMemory: { try ModelContainerSetup.makeInMemory() }
            ),
            log: { _ in }
        )

        let container = try #require(boot.container)
        #expect(boot.isOnDisk)

        let before = try ModelContext(container).fetch(
            FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.sequenceNumber)])
        )
        #expect(before.count == expectedCount)
        #expect(before.first?.previewText == expectedFirstPreview)

        let service = StorageService(
            modelContainer: container,
            environment: .testing {
                $0.sequenceCounter = SequenceCounter(defaults: ThrowawayDefaults.make())
            }
        )
        let text = "ingested after upgrade"
        let payload = Data(text.utf8)
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: payload,
            payloadString: text,
            frontmostBundleID: "com.apple.Notes",
            timestamp: .now,
            contentHash: hash
        ))

        let after = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(after.count == expectedCount + 1)
    }
}
