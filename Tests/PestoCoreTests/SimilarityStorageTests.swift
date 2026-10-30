// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Look-alike clips in storage")
struct SimilarityStorageTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
    }

    private func message(_ name: String, _ order: Int) -> String {
        "Hi \(name), your order \(order) has shipped and should arrive on Friday. Thanks for shopping with us today!"
    }

    private func ingest(_ service: StorageService, _ text: String) async throws -> UUID {
        let id = UUID()
        let capture = PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
        try await service.ingest(capture, preferredItemID: id)
        return id
    }

    @Test("a signature is stored sealed with the clip and found again after the index is reloaded")
    func whenClipsSigned_thenFamilyFoundAfterReload() async throws {
        let service = StorageService(modelContainer: container)
        var ids: [UUID] = []
        for (name, order) in [("Ana", 11), ("Bo", 22), ("Cy", 33)] {
            try await ids.append(ingest(service, message(name, order)))
        }
        let other = try await ingest(
            service,
            "Completely different text about weather forecasts and rainfall in the northern hills"
        )

        let before = await service.lookalikes(of: ids[0])
        #expect(Set(before.map(\.id)) == Set(ids.dropFirst()))

        await service.dropSimilarityIndex()
        #expect(await service.lookalikes(of: ids[0]).isEmpty)
        try await service.loadSimilarityIndex()
        let after = await service.lookalikes(of: ids[0])
        #expect(Set(after.map(\.id)) == Set(ids.dropFirst()))
        #expect(!after.contains { $0.id == other })
    }

    @Test("a deleted clip leaves the index, and clearing the history empties it")
    func whenDeletedOrCleared_thenForgotten() async throws {
        let service = StorageService(modelContainer: container)
        let first = try await ingest(service, message("Ana", 1))
        let second = try await ingest(service, message("Bo", 2))
        let third = try await ingest(service, message("Cy", 3))

        _ = try await service.deleteItems(ids: [second], reason: .user)
        #expect(await Set(service.lookalikes(of: first).map(\.id)) == [third])

        _ = try await service.clearNonPinned(in: .all)
        #expect(await service.lookalikes(of: first).isEmpty)
    }

    @Test("pastes on different days are counted as days, once each, and a family reaches the suggestion facts")
    func whenPastedOnDays_thenHabitAndFamilyInFacts() async throws {
        let service = StorageService(modelContainer: container)
        let ids = try await (0..<3).asyncMap { try await self.ingest(service, self.message("P\($0)", $0)) }
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for offset in [0, 0, 1, 2] {
            try await service.notePasted(id: ids[0], at: day.addingTimeInterval(Double(offset) * 86_400))
        }

        let facts = try await service.shelfSuggestionFacts(unavailableSlots: [])

        let clip = try #require(facts.clips.first { $0.id == ids[0] })
        #expect(clip.familySize == 3)
        #expect(clip.familyRepresentative == ids.min { $0.uuidString < $1.uuidString })
        let item = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
            .first { $0.id == ids[0] })
        #expect(item.metadata.pasteDays?.count == 3)
    }

    @Test("a pinned look-alike is not counted in a family, so pinning one clip ends the offer for the others")
    func whenAMemberIsPinned_thenFamilyShrinks() async throws {
        let service = StorageService(modelContainer: container)
        let ids = try await (0..<3).asyncMap { try await self.ingest(service, self.message("P\($0)", $0)) }
        _ = try await service.togglePinned(id: ids[1])
        try await service.notePasted(id: ids[0])

        let facts = try await service.shelfSuggestionFacts(unavailableSlots: [])

        let clip = try #require(facts.clips.first { $0.id == ids[0] })
        #expect(clip.familySize == 2)
    }

    @Test("a secret, a short text and a clip that expires are never signed")
    func whenNotEligible_thenNoSignature() {
        #expect(!TextSignature.isEligible(isTextual: true, isSensitive: true, expires: false, length: 100))
        #expect(!TextSignature.isEligible(isTextual: true, isSensitive: false, expires: true, length: 100))
        #expect(!TextSignature.isEligible(isTextual: true, isSensitive: false, expires: false, length: 10))
        #expect(!TextSignature.isEligible(isTextual: false, isSensitive: false, expires: false, length: 100))
        #expect(TextSignature.isEligible(isTextual: true, isSensitive: false, expires: false, length: 100))
    }

    @Test("clips that arrived before signing are signed in small steps until the pass says it is finished")
    func whenBackfilled_thenAllSignedAndPassFinishes() async throws {
        let service = StorageService(modelContainer: container)
        let ids = try await (0..<5).asyncMap { try await self.ingest(service, self.message("P\($0)", $0)) }
        await service.dropSimilarityIndex()
        let context = ModelContext(container)
        for item in try context.fetch(FetchDescriptor<ClipboardItem>()) {
            item.updateMetadata { $0.signature = nil }
        }
        try context.save()

        let first = try await service.signMissingClips(limit: 2, before: nil)
        #expect(!first.isFinished)
        var pass = first
        while !pass.isFinished {
            pass = try await service.signMissingClips(limit: 2, before: pass.nextCursor)
        }

        #expect(await Set(service.lookalikes(of: ids[0]).map(\.id)) == Set(ids.dropFirst()))
    }

    @Test("newest clips that can never be signed do not stop the older ones from being reached, and the pass ends")
    func whenNewestClipsAreUnsignable_thenOlderOnesAreStillSigned() async throws {
        let service = StorageService(modelContainer: container)
        let ids = try await (0..<3).asyncMap { try await self.ingest(service, self.message("P\($0)", $0)) }
        for index in 0..<30 {
            _ = try await ingest(service, "short \(index)")
        }
        await service.dropSimilarityIndex()
        let context = ModelContext(container)
        for item in try context.fetch(FetchDescriptor<ClipboardItem>()) {
            item.updateMetadata { $0.signature = nil }
        }
        try context.save()

        var pass = try await service.signMissingClips(limit: 2, before: nil)
        var passes = 1
        while !pass.isFinished, passes < 100 {
            pass = try await service.signMissingClips(limit: 2, before: pass.nextCursor)
            passes += 1
        }

        #expect(pass.isFinished)
        #expect(await Set(service.lookalikes(of: ids[0]).map(\.id)) == Set(ids.dropFirst()))
    }

    @Test("a saved snippet is never signed, so it cannot join the family it came from")
    func whenSnippetSaved_thenItIsNotInTheIndex() async throws {
        let service = StorageService(modelContainer: container)
        let ids = try await (0..<3).asyncMap { try await self.ingest(service, self.message("P\($0)", $0)) }
        let template = "Hi {{input:Name}}, your order {{input:Number}} has shipped and should arrive on Friday. "
            + "Thanks for shopping with us today!"
        let snippet = try #require(await service.addSnippet(template))

        #expect(await service.lookalikes(of: ids[0]).map(\.id).contains(snippet) == false)
        #expect(await service.lookalikes(of: snippet).isEmpty)
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            try await result.append(transform(element))
        }
        return result
    }
}
