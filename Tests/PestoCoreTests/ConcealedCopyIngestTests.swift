// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("A concealed copy that was kept", .serialized)
@MainActor
struct ConcealedCopyIngestTests {
    @Test("is hidden as a credential, because it may be a username or a password")
    func whenKeptConcealedCopy_thenHiddenAsACredential() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container)

        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data("correct-horse-battery".utf8),
            payloadString: "correct-horse-battery",
            frontmostBundleID: "com.1password.1password",
            contentHash: UUID().uuidString,
            isConcealed: true
        ))

        let item = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.sensitivity == .credential)
        let preview = item.sensitivityMaskedPreview ?? ""
        #expect(preview.hasPrefix("Hidden by "), Comment(rawValue: preview))
        #expect(!item.gridPreview.contains("correct-horse"))
    }

    @Test("is removed by itself after a day, so a password does not sit in the history")
    func whenKeptConcealedCopy_thenItExpires() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container)
        let now = Date()

        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data("hunter2".utf8), payloadString: "hunter2",
            frontmostBundleID: "com.1password.1password", timestamp: now, contentHash: UUID().uuidString,
            isConcealed: true
        ))

        let item = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        let expiry = try #require(item.expiresAt)
        #expect(abs(expiry.timeIntervalSince(now) - 86_400) < 5)
    }
}
