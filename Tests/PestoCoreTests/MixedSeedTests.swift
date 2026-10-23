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

    @Test("every clip is distinct")
    func clipsAreDistinct() {
        let hashes = MixedSeed.captures(count: 120).map(\.contentHash)
        #expect(Set(hashes).count == hashes.count)
    }
}
