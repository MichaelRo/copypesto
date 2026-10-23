// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@Suite("SeedFixtures")
struct SeedFixturesTests {
    private func textTypes(of captures: [PasteboardCapture]) -> Set<ClipboardType> {
        Set(captures.compactMap(\.payloadString).map { ContentClassifier.classify(text: $0).type })
    }

    @Test("the empty profile seeds nothing")
    func whenEmpty_thenNoCaptures() {
        #expect(SeedFixtures.captures(for: .empty).isEmpty)
    }

    @Test("the basic profile covers every card type the grid renders")
    func whenBasic_thenCoversCardTypes() {
        let captures = SeedFixtures.captures(for: .basic)
        let types = textTypes(of: captures)

        #expect(captures.count == 14)
        #expect(types.isSuperset(of: [.text, .code, .url, .color]))
        #expect(captures.contains { $0.typeIdentifier == NSPasteboard.PasteboardType.png.rawValue })
    }

    @Test("the basic profile includes content that must be masked")
    func whenBasic_thenIncludesSensitiveContent() {
        let sensitive = SeedFixtures.captures(for: .basic)
            .compactMap(\.payloadString)
            .filter { SensitiveContentDetector.detect(in: $0) != nil }

        #expect(sensitive.count >= 2)
    }

    @Test("every seeded capture has a distinct content hash so nothing is deduplicated")
    func whenBasic_thenUniqueHashes() {
        let hashes = SeedFixtures.captures(for: .basic).map(\.contentHash)
        #expect(Set(hashes).count == hashes.count)
    }

    @Test("the large profile seeds 5,000 distinct items")
    func whenLarge_thenFiveThousandUnique() {
        let captures = SeedFixtures.captures(for: .large)
        #expect(captures.count == 5000)
        #expect(Set(captures.map(\.contentHash)).count == 5000)
    }

    @Test("the hash matches the payload so dedupe behaves like a live capture")
    func hash_matchesPayload() {
        for capture in SeedFixtures.captures(for: .basic) {
            #expect(capture.contentHash == SeedFixtures.hash(of: capture.payload))
        }
    }

    @Test("captures are one minute apart, oldest first, ending at the reference time")
    func timestamps_areOrderedOneMinuteApart() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let captures = SeedFixtures.captures(for: .basic, now: now)

        let stamps = captures.map(\.timestamp)
        #expect(stamps == stamps.sorted())
        #expect(stamps.last == now)
        #expect(zip(stamps, stamps.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 60 })
    }

    @Test("seeding is deterministic")
    func whenSeededTwice_thenIdentical() {
        let first = SeedFixtures.captures(for: .basic).map(\.contentHash)
        let second = SeedFixtures.captures(for: .basic).map(\.contentHash)
        #expect(first == second)
    }
}
