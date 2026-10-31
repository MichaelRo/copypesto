// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("The key canary opens a few small clips")
    struct KeyCanaryTests {
        private func store(_ texts: [String]) async throws -> ModelContainer {
            let container = try ModelContainerSetup.makeInMemory()
            let service = StorageService(modelContainer: container)
            for text in texts {
                let payload = Data(text.utf8)
                try await service.ingest(PasteboardCapture(
                    typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
                    contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
                ))
            }
            return container
        }

        @Test("an empty history gives no answer, so nothing is offered to wipe")
        @MainActor
        func whenThereIsNoHistory_thenNoAnswer() async throws {
            let container = try await store([])

            #expect(AppDelegate.keyOpensSomeHistory(in: ModelContext(container)) == nil)
        }

        @Test("a history this Mac's key opens answers yes")
        @MainActor
        func whenTheKeyOpensTheHistory_thenYes() async throws {
            let container = try await store(["a small clip", "another small clip"])

            #expect(AppDelegate.keyOpensSomeHistory(in: ModelContext(container)) == true)
        }
    }
}
