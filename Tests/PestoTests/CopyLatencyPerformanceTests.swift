// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import PestoCore
import SwiftData
import Testing
import UniformTypeIdentifiers
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
            "picture 1920x1080": 200, "screenshot 2880x1800": 200, "gif 24 frames": 100, "large clip 5 MB": 200
        ]

        private func makeStore() throws -> (ModelContainer, URL) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-copy-latency-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let container = try ModelContainerSetup.openClips(storeURL: directory.appendingPathComponent("clips.store")
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

        /// Three screenshots unlike each other, so none is nominated as a lookalike: this times the hash and the
        /// fingerprint at copy time and the save.
        @Test("a full-screen 5K screenshot becomes a card under 200 ms without blocking on OCR")
        func fullScreenScreenshot_ingestsUnder200ms() async throws {
            let (container, directory) = try makeStore()
            defer { try? FileManager.default.removeItem(at: directory) }
            let service = StorageService(modelContainer: container)
            let clock = ContinuousClock()
            var durations: [Double] = []
            for (variant, pattern) in [0b1010_1010, 0b0101_0101, 0b1111_0000].enumerated() {
                let capture = PasteboardCapture(
                    typeIdentifier: "public.png",
                    payload: PictureFixtures.png(width: 5120, height: 2880, fill: .bands(pattern: pattern)),
                    frontmostBundleID: "com.apple.screencaptureui",
                    contentHash: "5k-screenshot-\(variant)"
                )
                let start = clock.now
                try await service.ingest(capture)
                durations.append(PerfReport.milliseconds(clock.now - start))
            }
            let timing = PerfReport.timing(of: durations)
            PerfReport.emit("ingest 5K screenshot 5120x2880: \(timing.text)")
            let imageType = ClipboardType.image.rawValue
            let cards = try ModelContext(container).fetchCount(
                FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.typeRaw == imageType })
            )
            #expect(cards == 3, "each screenshot is a new card, not a duplicate")
            if !RunEnvironment.isCI {
                #expect(
                    timing.median < 200,
                    "5K screenshot ingest took \(timing.median) ms; budget < 200 ms"
                )
            }
            await service.waitForBackgroundWork()
        }

        /// The same window six times with one line changed: the 8×8 hash nominates each earlier screenshot and its
        /// fingerprint rules it out with no full decode (ADR 0077; 262 to 620 ms on these pictures without that). The
        /// last copy repeats the sixth one's pixels in another file, which is compared pixel by pixel and only
        /// reported.
        @Test("a 5K screenshot that looks like earlier ones becomes a card under 200 ms")
        func lookalikeScreenshot_ingestsUnder200ms() async throws {
            let (container, directory) = try makeStore()
            defer { try? FileManager.default.removeItem(at: directory) }
            let service = StorageService(modelContainer: container)
            let clock = ContinuousClock()
            let payloads = (0..<6).map { PictureFixtures.png(width: 5120, height: 2880, fill: .window(edit: $0 * 5)) }
            let hashes = try payloads.map { try #require(PerceptualHasher.hash(imageData: $0)) }
            for hash in hashes.dropFirst() {
                let distance = try #require(PerceptualHasher.hammingDistance(hashes[0], hash))
                #expect(distance <= PerceptualHasher.similarityThreshold, "the pictures must be nominated to count")
            }
            var durations: [Double] = []
            for (index, payload) in payloads.enumerated() {
                let capture = PasteboardCapture(
                    typeIdentifier: "public.png", payload: payload,
                    frontmostBundleID: "com.apple.screencaptureui", contentHash: "5k-lookalike-\(index)"
                )
                let start = clock.now
                try await service.ingest(capture)
                durations.append(PerfReport.milliseconds(clock.now - start))
            }
            let lookalikes = PerfReport.timing(of: Array(durations.dropFirst()))
            let each = durations.map { String(format: "%.0f", $0) }.joined(separator: ", ")
            PerfReport.emit("ingest 5K lookalike screenshot: \(lookalikes.text); each \(each) ms")
            let imageType = ClipboardType.image.rawValue
            let images = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.typeRaw == imageType })
            #expect(try ModelContext(container).fetchCount(images) == 6, "each screenshot is a new card")

            let again = PasteboardCapture(
                typeIdentifier: "public.png", payload: Self.withOtherDensity(payloads[5]),
                frontmostBundleID: "com.apple.screencaptureui", contentHash: "5k-lookalike-again"
            )
            let start = clock.now
            try await service.ingest(again)
            let repeated = PerfReport.milliseconds(clock.now - start)
            PerfReport.emit("ingest 5K screenshot with the same pixels again: \(String(format: "%.0f", repeated)) ms")
            #expect(try ModelContext(container).fetchCount(images) == 6, "the same pixels are the same card")
            if !RunEnvironment.isCI {
                let slowest = durations.dropFirst().max() ?? 0
                #expect(slowest < 200, "5K lookalike ingest took \(slowest) ms at worst; budget < 200 ms")
            }
            await service.waitForBackgroundWork()
        }

        private static func withOtherDensity(_ png: Data) -> Data {
            let output = NSMutableData()
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let destination = CGImageDestinationCreateWithData(
                      output, UTType.png.identifier as CFString, 1, nil
                  ) else { preconditionFailure("cannot re-encode the fixture") }
            let density = [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary
            CGImageDestinationAddImage(destination, image, density)
            precondition(CGImageDestinationFinalize(destination))
            return output as Data
        }
    }
}
