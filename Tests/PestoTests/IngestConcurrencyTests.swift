// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

private struct SlowRecognizer: TextRecognizing {
    func recognize(imageData _: Data) async -> String? {
        try? await Task.sleep(for: .milliseconds(300))
        return nil
    }
}

extension HostedGlobals {
    @Suite("Two copies of one picture arriving together are stored once")
    struct IngestConcurrencyTests {
        @Test("a second copy that arrives while the first is being read is the same clip, not a new one")
        func whenTheSameCopyArrivesTwiceWhileTheFirstIsInOCR_thenOneClipIsStored() async throws {
            let container = try ModelContainerSetup.makeInMemory().synced
            let service = StorageService(
                modelContainer: container, environment: .testing { $0.textRecognizer = SlowRecognizer() }
            )
            let picture = PictureFixtures.png(width: 64, height: 64, fill: .noise)
            let capture = PasteboardCapture(
                typeIdentifier: "public.png", payload: picture, timestamp: .now,
                contentHash: SHA256.hash(data: picture).map { String(format: "%02x", $0) }.joined()
            )

            async let first: Void = service.ingest(capture)
            async let second: Void = service.ingest(capture)
            _ = try await (first, second)
            await service.waitForBackgroundWork()

            #expect(try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()) == 1)
        }
    }
}
