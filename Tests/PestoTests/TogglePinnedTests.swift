// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Pinning a clip through the storage service")
    struct TogglePinnedTests {
        @Test("toggling pins an unpinned clip, then unpins it, and says which; an unknown id says nothing")
        func whenToggled_thenPinnedStateFlipsAndIsReported() async throws {
            let container = try ModelContainerSetup.makeInMemory()
            let service = StorageService(modelContainer: container)
            let payload = Data("pin me".utf8)
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: "pin me",
                contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            ))
            let id = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first?.id)

            #expect(try await service.togglePinned(id: id) == true)
            #expect(try await service.togglePinned(id: id) == false)
            #expect(try await service.togglePinned(id: UUID()) == nil)
        }
    }
}
