// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PestoCore

@Suite("What happens to a capture the watcher hands over")
struct CapturePipelineTests {
    private final class Outlets: Sendable {
        private let stored = Mutex(0)
        private let refusals = Mutex<[String]>([])

        var storedCount: Int {
            stored.withLock { $0 }
        }

        var refused: [String] {
            refusals.withLock { $0 }
        }

        func didStore() {
            stored.withLock { $0 += 1 }
        }

        func didRefuse(_ message: String) {
            refusals.withLock { $0.append(message) }
        }
    }

    private let container: ModelContainer
    private let service: StorageService
    private let appendMode = AppendModeCoordinator()
    private let outlets = Outlets()

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container, environment: .testing())
    }

    private func pipeline() -> CapturePipeline {
        let outlets = outlets
        return CapturePipeline(
            storage: service, appendMode: appendMode,
            didStore: { outlets.didStore() }, didRefuse: { outlets.didRefuse($0) }
        )
    }

    private func capture(_ text: String, at seconds: Double) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: Date(timeIntervalSince1970: seconds),
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func texts() throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)]))
            .compactMap { $0.blob?.decryptedText() }
    }

    @Test("a capture is stored, and the outlet that plays the copy sound is told once")
    func whenCaptured_thenStoredAndAnnounced() async throws {
        await pipeline().handle(capture("a plain copy", at: 1000))

        #expect(try texts() == ["a plain copy"])
        #expect(outlets.storedCount == 1)
        #expect(outlets.refused.isEmpty)
    }

    @Test("two copies in a row are two clips")
    func whenCapturedTwice_thenTwoClips() async throws {
        let pipeline = pipeline()
        await pipeline.handle(capture("first", at: 1000))
        await pipeline.handle(capture("second", at: 2000))

        #expect(try texts() == ["first", "second"])
        #expect(outlets.storedCount == 2)
    }

    @Test("after a double ⌘C the capture is appended to the latest clip, once")
    func whenDoubleCopy_thenAppended() async throws {
        let pipeline = pipeline()
        await pipeline.handle(capture("first part", at: 1000))
        await appendMode.setAppendMode()

        await pipeline.handle(capture("second part", at: 2000))
        await pipeline.handle(capture("an unrelated copy", at: 3000))

        #expect(try texts() == ["first part\nsecond part", "an unrelated copy"])
    }

    @Test("a copy over the size limit is refused with the policy's message and nothing is stored or announced")
    func whenTooLarge_thenRefusedWithItsMessage() async throws {
        let payload = Data(count: ClipSizePolicy.maxTextBytes + 1)
        let huge = PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: nil,
            timestamp: Date(timeIntervalSince1970: 1000), contentHash: "huge"
        )

        await pipeline().handle(huge)

        #expect(try texts().isEmpty)
        #expect(outlets.storedCount == 0)
        #expect(outlets.refused == [ClipSizePolicy.message(
            byteCount: payload.count, typeIdentifier: "public.utf8-plain-text"
        )])
    }
}
