// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

@Suite("The command bar's tag and app suggestions come from the storage actor", .serialized)
struct CommandBarSuggestionsTests {
    private let container: ModelContainer
    private let service: StorageService
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    init() async throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
    }

    private func ingest(_ text: String, minutesAgo: Double) async throws {
        let payload = Data(text.utf8)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: text,
            timestamp: base.addingTimeInterval(-minutesAgo * 60),
            contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        ))
    }

    private func label(_ text: String, tags: [String], app: (id: String, name: String)?) throws {
        let context = ModelContext(container)
        let item = try #require(try context.fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.displayPreviewText == text })
        item.tags = tags
        item.sourceBundleID = app?.id
        item.sourceAppName = app?.name
        try context.save()
    }

    @Test("an empty history suggests nothing")
    func whenEmpty_thenNothing() async throws {
        let result = try await service.commandBarSuggestions()
        #expect(result == CommandBarSuggestions.empty)
    }

    @Test("tags and apps are ranked by how many clips carry them")
    func whenHistoryHasTagsAndApps_thenRanked() async throws {
        try await ingest("one", minutesAgo: 30)
        try await ingest("two", minutesAgo: 20)
        try await ingest("three", minutesAgo: 10)
        try label("one", tags: ["work", "ops"], app: ("com.apple.Notes", "Notes"))
        try label("two", tags: ["work"], app: ("com.apple.Notes", "Notes"))
        try label("three", tags: ["home"], app: ("com.apple.Safari", "Safari"))

        let result = try await service.commandBarSuggestions()

        #expect(result.topTags == ["work", "home", "ops"])
        #expect(result.topApps.map(\.bundleID) == ["com.apple.Notes", "com.apple.Safari"])
        #expect(result.topApps.first?.name == "Notes")
    }

    @Test("the limits apply and every page of a long history is counted")
    func whenHistoryIsLong_thenAllPagesCountAndLimitsApply() async throws {
        for index in 0..<7 {
            try await ingest("clip \(index)", minutesAgo: Double(index))
            try label("clip \(index)", tags: ["shared", "tag\(index)"], app: nil)
        }

        let result = try await service.commandBarSuggestions(tagLimit: 3, appLimit: 5, batchSize: 2)

        #expect(result.topTags.first == "shared")
        #expect(result.topTags.count == 3)
    }

    @Test("the history reports whether any clip came from another device")
    func whenAClipIsRemote_thenSuggestionsSaySo() async throws {
        try await ingest("local", minutesAgo: 10)
        #expect(try await service.commandBarSuggestions().hasRemoteClips == false)

        let payload = Data("phone".utf8)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: "phone",
            timestamp: base, contentHash: "remote-hash", isRemote: true
        ))

        #expect(try await service.commandBarSuggestions().hasRemoteClips)
    }
}
