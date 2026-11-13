// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Mixed history seed")
struct MixedSeedTests {
    @Test("it holds text, links, code, colours and large pictures, each picture different")
    func hasEveryKind() {
        let captures = MixedSeed.captures(count: 36)
        let pictures = captures.filter { $0.typeIdentifier.contains("png") }
        #expect(pictures.count == 3)
        #expect(Set(pictures.map(\.contentHash)).count == 3, "pictures must not dedupe into one clip")
        #expect(pictures.allSatisfy { $0.payload.count > 100_000 }, "a picture should be screenshot-sized")
        let strings = captures.compactMap(\.payloadString)
        #expect(strings.contains { $0.hasPrefix("https://") })
        #expect(strings.contains { $0.hasPrefix("func ") })
        #expect(strings.contains { $0.hasPrefix("#") && $0.count == 7 })
    }

    @Test("the same count gives the same history, so two measurements compare")
    func isDeterministic() {
        let first = MixedSeed.captures(count: 14).map(\.contentHash)
        let second = MixedSeed.captures(count: 14).map(\.contentHash)
        #expect(first == second)
    }

    @Test("the mixed profile is MixedSeed's 1,200 clips and nothing else: the benches compare runs over time on it")
    func whenMixedProfile_thenItIsExactlyMixedSeed() {
        let profile = SeedFixtures.captures(for: .mixed)
        #expect(profile.count == 1200, "changing the size of .mixed breaks every recorded bench; add a new profile")
        #expect(MixedSeed.count == 1200)
        #expect(
            profile.map(\.contentHash) == MixedSeed.captures().map(\.contentHash),
            ".mixed no longer hands out MixedSeed: add a new SeedProfile for another history"
        )
    }

    @Test("every clip is distinct")
    func clipsAreDistinct() {
        let hashes = MixedSeed.captures(count: 120).map(\.contentHash)
        #expect(Set(hashes).count == hashes.count)
    }
}
