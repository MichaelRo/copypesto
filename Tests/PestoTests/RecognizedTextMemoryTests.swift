// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import Pesto
@testable import PestoCore

private struct ReadingProse: TextRecognizing {
    let text: String
    func recognize(imageData _: Data) async -> String? {
        text
    }
}

private struct RunResult {
    let growthMB: Double
    let seconds: Double
    let bytesOnDisk: Int
}

extension HostedGlobals {
    /// What keeping a picture's whole text (ADR 0034) costs: footprint after a run of screenshots whose text is as long
    /// as the cap allows, against the same run with a 500-character text, and the time the reading takes after the card
    /// is on the shelf.
    @Suite("Memory and time kept after screenshots with long text", .serialized)
    @MainActor
    struct RecognizedTextMemoryTests {
        private func footprintMB() -> Double {
            Double(PeakMemory.footprintBytes()) / 1_048_576
        }

        private func prose(bytes: Int) -> String {
            let sentence = "The quarterly summary says revenue rose while costs held steady across every region. "
            return String(String(repeating: sentence, count: bytes / sentence.utf8.count + 1).prefix(bytes))
        }

        private func run(
            text: String,
            count: Int,
            seed: Int
        ) async throws
        -> RunResult {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-ocr-memory-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let container = try ModelContainerSetup.openClips(storeURL: directory.appendingPathComponent("clips.store"))
            let store = RecognizedTextStore(directory: directory.appendingPathComponent("text"))
            let service = StorageService(modelContainer: container, environment: .testing {
                $0.textRecognizer = ReadingProse(text: text)
                $0.recognizedTexts = store
                $0.nsfwMode = { .show }
            })
            try await service.ingest(ClipKindFixtures.text("warm up the pipeline"))
            let before = footprintMB()
            let start = ContinuousClock.now
            for index in 0..<count {
                let picture = PictureFixtures.png(width: 320 + seed * 40 + index, height: 200, fill: .noise)
                try await service.ingest(ClipKindFixtures.capture("public.png", payload: picture))
            }
            await service.waitForBackgroundWork()
            let elapsed = ContinuousClock.now - start
            try await Task.sleep(for: .seconds(1))
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory.appendingPathComponent("text"), includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            let size = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return RunResult(growthMB: footprintMB() - before, seconds: seconds, bytesOnDisk: size)
        }

        @Test(
            "keeping 100 KB of text for each of 150 screenshots leaves the footprint where short text leaves it",
            .enabled(if: ProcessInfo.processInfo.environment["PESTO_LONG_COPY_MEMORY"] == "1")
        )
        func ingest_longRecognizedText_staysFlat() async throws {
            try #require(!RunEnvironment.isCI, "memory deltas are only meaningful on a developer Mac")
            _ = try await run(text: prose(bytes: 600), count: 10, seed: 0)

            let control = try await run(text: prose(bytes: 600), count: 150, seed: 1)
            let long = try await run(text: prose(bytes: RecognizedText.maxBytes), count: 150, seed: 2)

            PerfReport.emit(String(
                format: "150 screenshots: 600-char text %+.0f MB in %.1f s; 100 KB text %+.0f MB in %.1f s, "
                    + "%.1f MB of sealed text on disk",
                control.growthMB, control.seconds, long.growthMB, long.seconds, Double(long.bytesOnDisk) / 1_048_576
            ))
            #expect(long.growthMB - control.growthMB < 40, "long text kept \(long.growthMB - control.growthMB) MB more")
            #expect(long.bytesOnDisk > 150 * 90_000)
        }
    }
}
