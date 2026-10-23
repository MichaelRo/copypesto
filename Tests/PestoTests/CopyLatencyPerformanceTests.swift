// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    /// How long a copy takes to become a saved clip, per kind, over a file-backed store that already holds 5,000
    /// clips (the dedup lookup and the save cost more there than in an empty in-memory store). The poll wait before
    /// the watcher sees a copy and the shelf's refresh after the save are in `scripts/bench-latency.sh`.
    @Suite("Ingest per kind over a 5,000-clip store", .serialized)
    @MainActor
    struct CopyLatencyPerformanceTests {
        /// How long `ingest` may take to return, which is when the clip is on the shelf. A picture, a GIF and a very
        /// large
        /// text are saved before they are judged (ADR 0006): 728 ms, 518 ms and 433 ms before.
        private static let budgetMilliseconds: [String: Double] = [
            "text": 50, "code": 50, "link": 50, "colour": 50, "file": 50,
            "picture 1920x1080": 400, "screenshot 2880x1800": 400, "gif 24 frames": 100, "large clip 5 MB": 200
        ]

        private func makeStore() throws -> (ModelContainer, URL) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-copy-latency-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let container = try ModelContainerSetup.openSynced(
                cloudKitEnabled: false, storeURL: directory.appendingPathComponent("clips.store")
            )
            let context = ModelContext(container)
            let encryption = BlobEncryption()
            for index in 0..<5000 {
                let item = ClipboardItem(
                    type: .text, previewText: "", contentHash: "seed-hash-\(index)", byteSize: 80,
                    deviceID: "perf", sequenceNumber: Int64(index)
                )
                let envelope = try encryption
                    .encrypt(Data("Seeded clip number \(index), a line of ordinary text.".utf8))
                item.previewCiphertext = envelope.ciphertext
                item.previewNonce = envelope.nonce
                context.insert(item)
            }
            try context.save()
            return (container, directory)
        }

        @Test(
            "each kind of copy is saved within its budget, and the numbers are reported",
            .enabled(
                if: !RunEnvironment.isCI,
                "saving a picture runs text recognition, which never returns on a hosted runner"
            )
        )
        func ingest_perKind() async throws {
            let (container, directory) = try makeStore()
            defer { try? FileManager.default.removeItem(at: directory) }
            let service = StorageService(modelContainer: container)
            let clock = ContinuousClock()

            // The app prewarms the recognizer at launch; the first read otherwise takes tens of seconds.
            let prewarm = clock.now
            await OCRService().prewarm()
            PerfReport
                .emit(
                    "ocr prewarm: \(String(format: "%.0f", PerfReport.milliseconds(clock.now - prewarm))) ms"
                )

            var samples: [String: [Double]] = [:]
            for variant in 0..<5 {
                for fixture in ClipKindFixtures.all(variant: variant) {
                    let start = clock.now
                    try await service.ingest(fixture.capture)
                    samples[fixture.name, default: []].append(PerfReport.milliseconds(clock.now - start))
                }
            }
            // The pictures are still being judged in the background; the store must outlive that.
            await service.waitForBackgroundWork()
            for fixture in ClipKindFixtures.all(variant: 0) {
                let all = samples[fixture.name] ?? []
                let warm = PerfReport.timing(of: Array(all.dropFirst()))
                PerfReport.emit("ingest \(fixture.name): first \(String(format: "%.1f", all[0])) ms; then \(warm.text)")
                if !RunEnvironment.isCI, let budget = Self.budgetMilliseconds[fixture.name] {
                    #expect(
                        warm.median < budget,
                        "\(fixture.name) ingest took \(warm.median) ms over 5,000 clips; budget \(budget) ms"
                    )
                }
            }
        }
    }
}
