// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Thumbnail service threading")
struct ThumbnailServiceThreadTests {
    @Test("a service the shared provider makes never runs on the main thread, even when asked for from it")
    @MainActor
    func whenAskedForOnTheMainActor_thenItRunsOffTheMainThread() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = await ThumbnailServices.shared.service(for: container)
        #expect(await service.isRunningOnMainThread() == false)
    }

    @Test("the provider hands the same service to every card of one store, so no card makes its own context")
    @MainActor
    func whenAskedForTwice_thenItIsOneService() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let first = await ThumbnailServices.shared.service(for: container)
        let second = await ThumbnailServices.shared.service(for: container)
        #expect(first === second)
    }

    @Test("a service built directly on the main actor runs there, which is why a card must not build one")
    @MainActor
    func whenBuiltOnTheMainActor_thenItRunsOnTheMainThread() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let service = ThumbnailService(modelContainer: container)
        #expect(await service.isRunningOnMainThread())
    }
}
