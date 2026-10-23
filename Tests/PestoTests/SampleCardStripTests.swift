// SPDX-License-Identifier: MIT
import Testing
@testable import Pesto

@Suite("SampleCardStrip")
@MainActor
struct SampleCardStripTests {
    @Test("the sample clips build, one for each kind, in a store of their own")
    func samplesBuild() throws {
        let samples = try #require(SampleCardStrip.Samples.make(kinds: SampleCardStrip.Kind.allCases))

        #expect(samples.items.count == SampleCardStrip.Kind.allCases.count)
        #expect(Set(samples.items.map(\.typeRaw)).count >= 4, "the strip should show several kinds of clip")
    }
}
