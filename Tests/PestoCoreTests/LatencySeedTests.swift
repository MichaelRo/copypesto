// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Latency seed")
struct LatencySeedTests {
    @Test("the latency seed has one clip of each kind, newest first in the order the bench presses ⌘1 to ⌘8")
    func whenSeeded_thenOneOfEachKindNewestFirst() {
        let captures = SeedFixtures.captures(for: .latency, now: Date(timeIntervalSince1970: 1_000_000))
        let newestFirst = captures.sorted { $0.timestamp > $1.timestamp }
        #expect(newestFirst.map(\.typeIdentifier) == [
            "public.utf8-plain-text", "public.utf8-plain-text", "public.url", "public.utf8-plain-text",
            "public.file-url", "public.png", "com.compuserve.gif", "public.utf8-plain-text"
        ])
        #expect(Set(captures.map(\.contentHash)).count == captures.count)
    }

    @Test("the last card is the large clip, the colour is a colour, the code is code")
    func whenSeeded_thenKindsClassify() {
        let newestFirst = SeedFixtures.captures(for: .latency).sorted { $0.timestamp > $1.timestamp }
        #expect(ContentClassifier.classify(text: newestFirst[1].payloadString ?? "").type == .code)
        #expect(ContentClassifier.classify(text: newestFirst[3].payloadString ?? "").type == .color)
        #expect(newestFirst[7].payload.count > 4_000_000)
        #expect(Data(newestFirst[6].payload.prefix(6)).isGIFHeader)
    }
}

private extension Data {
    var isGIFHeader: Bool {
        starts(with: Array("GIF89a".utf8)) || starts(with: Array("GIF87a".utf8))
    }
}
