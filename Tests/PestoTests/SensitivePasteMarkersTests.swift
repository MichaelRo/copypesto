// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Pasting a secret does not spread it", .serialized)
    @MainActor
    struct SensitivePasteMarkersTests {
        private let container: ModelContainer
        private let service: StorageService
        private let state = AppState()
        private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

        init() async throws {
            container = try ModelContainerSetup.makeInMemory().synced
            service = StorageService(modelContainer: container)
        }

        private func item(_ text: String) async throws -> ClipboardItem {
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                contentHash: UUID().uuidString
            ))
            return try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        }

        @Test("a clip with a secret is written with the concealed marker, so other managers skip it")
        func whenSecretPasted_thenConcealedMarkerPresent() async throws {
            let secret = try await item("4242 4242 4242 4242")
            #expect(secret.sensitivityRaw != nil)

            _ = state.writeItem(secret)

            #expect(AppPasteboard.general.types?.contains(concealed) == true)
            #expect(
                AppPasteboard.general.string(forType: .string) == "4242 4242 4242 4242",
                "the paste itself must work"
            )
        }

        @Test("an ordinary clip is written without any marker")
        func whenOrdinaryPasted_thenNoMarker() async throws {
            let ordinary = try await item("quarterly numbers")

            _ = state.writeItem(ordinary)

            #expect(AppPasteboard.general.types?.contains(concealed) == false)
        }
    }
}
