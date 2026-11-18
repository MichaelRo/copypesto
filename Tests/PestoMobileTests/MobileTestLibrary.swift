// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

/// A booted app state on an in-memory store, for tests that add clips through ingest and act on them.
@MainActor
struct MobileTestLibrary {
    let state: MobileAppState
    let service: StorageService
    let store: HistoryStore

    init(reveal: SecretReveal? = nil) async throws {
        state = MobileAppState(secretReveal: reveal ?? SecretReveal(
            authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace()
        ))
        state.boot(
            openers: .init(
                clips: { try ModelContainerSetup.makeInMemory() },
                inMemory: { try ModelContainerSetup.makeInMemory() }
            ),
            environment: { .testing() }
        )
        await state.launchWork?.value
        service = try #require(state.storageService)
        store = try #require(state.historyStore)
    }

    @discardableResult
    func add(_ text: String) async throws -> ClipboardItem {
        try await service.ingest(#require(ClipCapture.text(text)))
        return try await settle(text)
    }

    func settle(_ text: String? = nil) async throws -> ClipboardItem {
        await service.waitForBackgroundWork()
        store.refresh()
        try await store.waitForRefresh()
        guard let text else { return try #require(store.items.first) }
        return try #require(store.items.first { $0.gridPreview == text || $0.displayPreviewText == text })
    }

    func refreshed() async throws {
        await service.waitForBackgroundWork()
        store.refresh()
        try await store.waitForRefresh()
    }
}
