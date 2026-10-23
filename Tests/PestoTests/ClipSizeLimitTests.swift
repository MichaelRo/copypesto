// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("A copy over the size limit is refused, not stored")
    struct ClipSizeLimitTests {
        private let container: ModelContainer
        private let service: StorageService

        init() async throws {
            container = try ModelContainerSetup.makeInMemory().synced
            service = StorageService(modelContainer: container)
        }

        private func capture(_ text: String) -> PasteboardCapture {
            PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                timestamp: .now,
                contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            )
        }

        private func itemCount() throws -> Int {
            try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>())
        }

        @Test("text over 10 MB is refused with a message, and nothing is stored")
        func whenTextIsOverTheLimit_thenIngestThrowsAndStoresNothing() async throws {
            let text = String(repeating: "x", count: ClipSizePolicy.maxTextBytes + 1)

            let error = await #expect(throws: ClipSizePolicy.TooLarge.self) {
                try await service.ingest(capture(text))
            }

            #expect(error?.message == ClipSizePolicy.message(
                byteCount: text.utf8.count,
                typeIdentifier: "public.utf8-plain-text"
            ))
            #expect(try itemCount() == 0)
        }

        @Test("text a copy appends to the latest clip may not take it over the limit")
        func whenAppendingWouldPassTheLimit_thenRefusedAndTheClipIsUnchanged() async throws {
            let half = String(repeating: "a", count: ClipSizePolicy.maxTextBytes / 2 + 1)
            try await service.ingest(capture(half))
            let other = String(repeating: "b", count: ClipSizePolicy.maxTextBytes / 2 + 1)

            await #expect(throws: ClipSizePolicy.TooLarge.self) {
                try await service.appendToLatest(capture(other))
            }

            let item = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
            #expect(item.textLength == half.count)
        }

        @Test("a normal copy is still stored")
        func whenTextIsSmall_thenStored() async throws {
            try await service.ingest(capture("quarterly numbers for the board"))

            #expect(try itemCount() == 1)
        }
    }
}
