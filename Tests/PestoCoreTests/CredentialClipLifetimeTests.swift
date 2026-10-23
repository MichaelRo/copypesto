// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

private let manager = "com.1password.1password"
private let otherManager = "com.bitwarden.desktop"
private let concealed = ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]

@Suite("How long a kept password-manager copy lives")
struct CredentialClipLifetimeRuleTests {
    @Test("the copy lasts as long as the allowance that let it in, and never more than a day")
    func expiryIsTheEarlierOfTheAllowanceAndADay() {
        let now = Date()
        let quarterHour = now.addingTimeInterval(900)
        #expect(StorageService.concealedExpiry(timestamp: now, allowanceEnd: quarterHour) == quarterHour)
        #expect(StorageService.concealedExpiry(timestamp: now, allowanceEnd: now.addingTimeInterval(4 * 3600))
            == now.addingTimeInterval(4 * 3600))
        #expect(StorageService.concealedExpiry(timestamp: now, allowanceEnd: now.addingTimeInterval(30 * 3600))
            == now.addingTimeInterval(86_400))
        #expect(StorageService.concealedExpiry(timestamp: now, allowanceEnd: .distantFuture)
            == now.addingTimeInterval(86_400))
        #expect(StorageService.concealedExpiry(timestamp: now, allowanceEnd: nil) == now.addingTimeInterval(86_400))
    }

    @Test("the rules name when the allowance behind a concealed copy ends: the earliest of the possible apps")
    func rulesReportTheAllowanceEnd() {
        let now = Date()
        let rules = ExclusionRules(temporaryAllowances: [
            manager: now.addingTimeInterval(900), otherManager: now.addingTimeInterval(3600)
        ])
        #expect(rules.concealedKeepEnd(typeIdentifiers: concealed, sources: [manager], now: now)
            == now.addingTimeInterval(900))
        #expect(rules.concealedKeepEnd(typeIdentifiers: concealed, sources: [manager, otherManager], now: now)
            == now.addingTimeInterval(900))
        #expect(rules.concealedKeepEnd(
            typeIdentifiers: concealed,
            sources: ["com.apple.Safari", otherManager],
            now: now
        )
            == now.addingTimeInterval(3600))
    }

    @Test("a copy that is not concealed, or comes from no allowed app, has no allowance end")
    func noEndWithoutAnAllowance() {
        let now = Date()
        let rules = ExclusionRules(temporaryAllowances: [manager: now.addingTimeInterval(900)])
        #expect(rules
            .concealedKeepEnd(typeIdentifiers: ["public.utf8-plain-text"], sources: [manager], now: now) == nil)
        #expect(rules.concealedKeepEnd(typeIdentifiers: concealed, sources: ["com.apple.Safari"], now: now) == nil)
        #expect(rules.concealedKeepEnd(
            typeIdentifiers: concealed,
            sources: [manager],
            now: now.addingTimeInterval(901)
        ) == nil)
    }

    @Test("an allowance that is over or revoked shows up as ended, one still running does not")
    func endedAllowances() {
        let now = Date()
        let before = [manager: now.addingTimeInterval(10), otherManager: now.addingTimeInterval(900)]
        let after = [otherManager: now.addingTimeInterval(900)]
        #expect(ExclusionAllowances.ended(from: before, to: after) == [manager])
        #expect(ExclusionAllowances.ended(from: before, to: before).isEmpty)
        #expect(ExclusionAllowances.ended(from: [:], to: after).isEmpty)
        let shortened = [manager: now.addingTimeInterval(5), otherManager: now.addingTimeInterval(900)]
        #expect(ExclusionAllowances.ended(from: before, to: shortened).isEmpty)
    }
}

@Suite("Kept password-manager copies in the store", .serialized)
@MainActor
struct CredentialClipLifetimeStoreTests {
    private func makeService() async throws -> (StorageService, ModelContainer) {
        let container = try ModelContainerSetup.makeInMemory().synced
        let service = StorageService(modelContainer: container)
        return (service, container)
    }

    private func keep(
        _ text: String,
        from app: String,
        in service: StorageService,
        until end: Date?,
        at now: Date
    ) async throws {
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            frontmostBundleID: app, timestamp: now, contentHash: UUID().uuidString,
            isConcealed: true, concealedUntil: end
        ))
    }

    @Test("a copy kept under a 15-minute allowance is stamped to go when the allowance does")
    func ingestStampsTheAllowanceEnd() async throws {
        let (service, container) = try await makeService()
        let now = Date()
        try await keep("hunter2", from: manager, in: service, until: now.addingTimeInterval(900), at: now)

        let item = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.expiresAt == now.addingTimeInterval(900))
    }

    @Test("a copy kept until Pesto quits is still capped at a day")
    func untilQuitIsCappedAtADay() async throws {
        let (service, container) = try await makeService()
        let now = Date()
        try await keep("hunter2", from: manager, in: service, until: .distantFuture, at: now)

        let item = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        #expect(item.expiresAt == now.addingTimeInterval(86_400))
    }

    @Test("when an allowance ends, that app's kept copies go and nothing else does")
    func removingByApp() async throws {
        let (service, container) = try await makeService()
        let now = Date()
        try await keep("one", from: manager, in: service, until: .distantFuture, at: now)
        try await keep("two", from: otherManager, in: service, until: .distantFuture, at: now)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data("plain note".utf8), payloadString: "plain note",
            frontmostBundleID: manager, timestamp: now, contentHash: UUID().uuidString
        ))

        let removed = try await service.removeKeptConcealedCopies(from: [manager])

        #expect(removed == 1)
        let left = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(left.count == 2)
        #expect(left.contains { $0.sourceBundleID == otherManager && $0.sensitivity == .credential })
        #expect(left.contains { $0.sourceBundleID == manager && $0.sensitivity == nil })
    }

    @Test("a kept copy that also looks like a secret keeps the secret's category and still goes with its allowance")
    func keptSecretGoesToo() async throws {
        let (service, container) = try await makeService()
        let now = Date()
        let key = "sk-ant-api03-fakekey1234567890fakekey1234567890"
        try await keep(key, from: manager, in: service, until: .distantFuture, at: now)
        try await keep("two", from: otherManager, in: service, until: .distantFuture, at: now)
        let stored = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(stored.contains { $0.sourceBundleID == manager && $0.sensitivity != .credential })

        let removed = try await service.removeKeptConcealedCopies(from: [manager])

        #expect(removed == 1)
        let left = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(left.map(\.sourceBundleID) == [otherManager])
    }

    @Test("with no app named, every kept copy goes, which is what a launch does because no allowance survives it")
    func removingAll() async throws {
        let (service, container) = try await makeService()
        let now = Date()
        try await keep("one", from: manager, in: service, until: .distantFuture, at: now)
        try await keep("two", from: otherManager, in: service, until: .distantFuture, at: now)

        let removed = try await service.removeKeptConcealedCopies(from: nil)

        #expect(removed == 2)
        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }

    @Test("a kept copy the person pinned stays")
    func pinnedStays() async throws {
        let (service, container) = try await makeService()
        let now = Date()
        try await keep("one", from: manager, in: service, until: .distantFuture, at: now)
        let context = ModelContext(container)
        try #require(try context.fetch(FetchDescriptor<ClipboardItem>()).first).isPinned = true
        try context.save()

        let removed = try await service.removeKeptConcealedCopies(from: nil)

        #expect(removed == 0)
        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).count == 1)
    }
}
