// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import Pesto
@testable import PestoCore

private struct NoText: TextRecognizing {
    func recognize(imageData _: Data) async -> String? {
        nil
    }
}

private struct NeverSensitive: ImageSensitivityScreening {
    func isSensitive(imageData _: Data) async -> Bool {
        false
    }
}

extension HostedGlobals {
    /// What the app keeps after a day of long copies. The footprint that matters is what stays once the copies are
    /// stored, so it is read after the work, not at its peak (`scripts/bench-latency.sh memory` measures the whole
    /// app).
    @Suite("Memory kept after long copies", .serialized)
    @MainActor
    struct LongCopyMemoryTests {
        private func footprintMB() -> Double {
            Double(PeakMemory.footprintBytes()) / 1_048_576
        }

        private func makeService() async throws -> (StorageService, URL) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-long-copy-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let container = try ModelContainerSetup.openClips(storeURL: directory.appendingPathComponent("clips.store")
            )
            let service = StorageService(modelContainer: container)
            return (service, directory)
        }

        private func pictures(_ service: StorageService, count: Int, seed: Int) async throws -> Double {
            let before = footprintMB()
            for run in 0..<count {
                let picture = PictureFixtures.png(width: 2000 + seed * 100 + run, height: 1250, fill: .noise)
                try await service.ingest(ClipKindFixtures.capture("public.png", payload: picture))
            }
            try await Task.sleep(for: .seconds(1))
            return footprintMB() - before
        }

        @Test(
            "storing megabyte-sized copies and screenshots does not keep growing the footprint",
            .enabled(if: ProcessInfo.processInfo.environment["PESTO_LONG_COPY_MEMORY"] == "1")
        )
        func ingest_longCopies_releasesTheirData() async throws {
            try #require(!RunEnvironment.isCI, "memory deltas are only meaningful on a developer Mac")
            await OCRService().prewarm()

            let (service, directory) = try await makeService()
            defer { try? FileManager.default.removeItem(at: directory) }
            try await service.ingest(ClipKindFixtures.text("warm up the pipeline"))
            let beforeTexts = footprintMB()
            for run in 0..<100 {
                let text = String(repeating: "A long copy of text, one megabyte of it. ", count: 25_000) + " \(run)"
                try await service.ingest(ClipKindFixtures.text(text))
            }
            let texts = footprintMB() - beforeTexts

            let (full, fullDirectory) = try await makeService()
            defer { try? FileManager.default.removeItem(at: fullDirectory) }
            var rounds: [Double] = []
            for round in 1...4 {
                try await rounds.append(pictures(full, count: 20, seed: round))
            }

            PerfReport.emit(String(
                format: "footprint kept: %+.0f MB after 100 x 1 MB texts; after four rounds of 20 pictures: "
                    + "%+.0f, %+.0f, %+.0f, %+.0f MB",
                texts, rounds[0], rounds[1], rounds[2], rounds[3]
            ))
            let withBoth = rounds[1] + rounds[2] + rounds[3]
            #expect(texts < 60, "100 long texts left \(texts) MB in the footprint")
            #expect(
                withBoth < 60,
                "60 more screenshots left \(withBoth) MB in the footprint, after the first 20 warmed it up"
            )
        }
    }
}
