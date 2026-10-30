// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI
import Testing
@testable import Pesto

extension HostedGlobals {
    /// Opening the hover card for the kinds of clip that cost something: building it, laying it out and letting its
    /// task read the whole clip. The pointer, the dwell and the panel are in `scripts/bench-latency.sh hover`.
    @Suite("Hover card build and memory", .serialized)
    @MainActor
    struct HoverCardPerformanceTests {
        private func ingest(
            _ capture: PasteboardCapture,
            into container: ModelContainer
        ) async throws
        -> ClipboardItem {
            let service = StorageService(modelContainer: container)
            let context = ModelContext(container)
            let known = try Set(context.fetch(FetchDescriptor<ClipboardItem>()).map(\.id))
            try await service.ingest(capture)
            return try #require(try context.fetch(FetchDescriptor<ClipboardItem>()).first { !known.contains($0.id) })
        }

        /// The card is built, laid out and given the run loop for 60 ms, which is when its `.task` reads the clip.
        private func open(_ item: ClipboardItem) -> Double {
            let clock = ContinuousClock()
            let start = clock.now
            let controller = NSHostingController(rootView: CardDetailPopover(item: item))
            _ = controller.view.fittingSize
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            _ = controller.view.fittingSize
            return PerfReport.milliseconds(clock.now - start) - 60
        }

        private var longCode: String {
            (0..<2500).map { "func step\($0)(_ value: Int) -> Int { return value &+ \($0) } // call site \($0)" }
                .joined(separator: "\n")
        }

        /// A resident-memory delta over one run can be negative (the allocator gives pages back), so a leak is judged
        /// by
        /// the slope: the second fifty opens must not grow memory the way the first fifty did.
        private func checkNoGrowth(opening picture: ClipboardItem) {
            for _ in 0..<50 {
                _ = open(picture)
            }
            let middle = PeakMemory.residentBytes()
            for _ in 0..<50 {
                _ = open(picture)
            }
            let lateGrowthMB = Double(PeakMemory.residentBytes() - middle) / 1_048_576
            PerfReport.emit(
                "hover-card memory, opens 51 to 100 of a picture: \(String(format: "%+.1f", lateGrowthMB)) MB resident"
            )
            if !RunEnvironment.isCI {
                #expect(lateGrowthMB < 10, "opens 51 to 100 of the hover card grew memory by \(lateGrowthMB) MB")
            }
        }

        @Test("the hover card opens within its budget for text, code and a picture, and does not grow memory")
        func open_perKind() async throws {
            let container = try ModelContainerSetup.makeInMemory()
            let kinds: [(String, PasteboardCapture)] = [
                ("short text", ClipKindFixtures.text("Dinner is at 7:30. Bring the basil from the balcony.")),
                (
                    "code 200 chars",
                    ClipKindFixtures.text("func total(_ values: [Int]) -> Int {\n    values.reduce(0, +)\n}\n")
                ),
                ("code 200 KB", ClipKindFixtures.text(longCode)),
                (
                    "text 900 KB",
                    ClipKindFixtures.text(String(
                        repeating: "The quick brown fox jumps over the lazy dog. ",
                        count: 20_000
                    ))
                ),
                (
                    "text 5 MB",
                    ClipKindFixtures.text(String(
                        repeating: "The quick brown fox jumps over the lazy dog. ",
                        count: 120_000
                    ))
                ),
                (
                    "picture",
                    ClipKindFixtures.capture(
                        "public.png",
                        payload: PictureFixtures.png(width: 1920, height: 1080, fill: .noise)
                    )
                )
            ]
            for (name, capture) in kinds {
                let item = try await ingest(capture, into: container)
                _ = open(item)
                let timing = PerfReport.timing(of: (0..<7).map { _ in open(item) })
                PerfReport
                    .emit("hover-card open \(name) (\(item.type.rawValue), \(item.byteSize) bytes): \(timing.text)")
                if !RunEnvironment.isCI {
                    #expect(timing.median < 30, "\(name) took \(timing.median) ms to open; budget 30 ms")
                }
            }

            let picture = try await ingest(
                ClipKindFixtures.capture(
                    "public.png",
                    payload: PictureFixtures.png(width: 1500, height: 1000, fill: .noise)
                ),
                into: container
            )
            _ = open(picture)
            checkNoGrowth(opening: picture)
        }
    }
}
