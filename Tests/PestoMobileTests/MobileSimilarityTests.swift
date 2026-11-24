// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("SimilarityIndex, Insights counts, and lock lifecycle on iOS")
@MainActor
struct MobileSimilarityTests {
    @Test("copying on iOS records pasteCount and pasteDays for Insights")
    func whenCopiedOnIOS_thenPasteCountAndDaysIncrement() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("Reusable prompt")
        #expect(item.pasteCount == 0)

        let copied = library.state.copy(item)
        #expect(copied)
        #expect(item.pasteCount == 1)
        #expect(item.metadata.pasteDays?.count == 1)
    }

    @Test("lookalikes finds similar clips and drops in-memory index on lock")
    func whenSimilarClipsExist_thenLookalikesMatchAndClearOnLock() async throws {
        let library = try await MobileTestLibrary(
            lock: MobileHistoryLock(
                authenticator: StubUserAuthenticator(available: true, grants: true),
                grace: AuthenticationGrace(),
                isEnabled: { true }
            )
        )
        let first = try await library.add(
            "Invoice INV-2026-001 for Acme Design submitted cleanly on Tuesday"
        )
        let second = try await library.add(
            "Invoice INV-2026-002 for Acme Design submitted cleanly on Tuesday"
        )
        _ = try await library.add(
            "Unrelated grocery shopping list with apples bananas milk"
        )

        try await library.service.loadSimilarityIndex()
        let matches = await library.service.lookalikes(of: second.id)
        #expect(matches.contains { $0.id == first.id })

        library.state.lockHistory()
        try await Task.sleep(for: .milliseconds(50))
        let afterDrop = await library.service.lookalikes(of: second.id)
        #expect(afterDrop.isEmpty)
    }
}
