// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Everyday history seed")
struct EverydaySeedTests {
    @Test("it holds what a clipboard really holds: screenshots, long links, chat, code, a secret, a colour")
    func hasEveryKind() {
        let captures = EverydaySeed.captures()
        let strings = captures.compactMap(\.payloadString)
        #expect(captures.count(where: { $0.typeIdentifier.contains("png") }) == 2)
        #expect(strings.contains { $0.hasPrefix("https://") && $0.count > 80 })
        #expect(strings.contains { $0.hasPrefix("SELECT ") })
        #expect(strings.contains { $0.hasPrefix("sk-ant-") })
        #expect(strings.contains { $0.hasPrefix("#") && $0.count == 7 })
        #expect(strings.contains { $0.count < 12 })
    }

    @Test("every clip is distinct and the history is the same every time")
    func isDeterministicAndDistinct() {
        let first = EverydaySeed.captures().map(\.contentHash)
        #expect(Set(first).count == first.count)
        #expect(first == EverydaySeed.captures().map(\.contentHash))
    }

    @Test("it is its own profile, and the benches' mixed history is not it")
    func whenProfiles_thenEverydayIsNotMixed() {
        let everyday = SeedFixtures.captures(for: .everyday).map(\.contentHash)
        #expect(everyday == EverydaySeed.captures().map(\.contentHash))
        #expect(everyday != SeedFixtures.captures(for: .mixed).map(\.contentHash))
        #expect(SeedProfile(rawValue: "everyday") == .everyday)
    }
}
