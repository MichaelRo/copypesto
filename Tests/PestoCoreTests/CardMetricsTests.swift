// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Card metrics")
struct CardMetricsTests {
    @Test("the named sizes keep the dimensions they always had")
    func namedWidths_keepTheirHeights() {
        #expect(CardMetrics.dimensions(width: 160) == CGSize(width: 160, height: 140))
        #expect(CardMetrics.dimensions(width: 180) == CGSize(width: 180, height: 160))
        #expect(CardMetrics.dimensions(width: 200) == CGSize(width: 200, height: 180))
    }

    @Test("a width outside the range is brought back into it")
    func outOfRange_isClamped() {
        #expect(CardMetrics.dimensions(width: 10).width == 150)
        #expect(CardMetrics.dimensions(width: 900).width == 240)
        #expect(CardMetrics.dimensions(width: 900).height == 220)
    }

    @Test("releasing the slider near a named size lands on it, and anywhere else stays put")
    func snap_landsOnPresetsOnly() {
        let presets = [160, 180, 200]
        #expect(CardMetrics.snap(183, to: presets) == 180)
        #expect(CardMetrics.snap(194, to: presets) == 200)
        #expect(CardMetrics.snap(170, to: presets) == 170)
        #expect(CardMetrics.snap(235, to: presets) == 235)
    }

    @Test("the slider has a labelled tick at each recommended width, evenly spaced across its range")
    func recommendedWidths_areEvenlySpaced() {
        let widths = CardMetrics.recommendedWidths
        #expect(widths.first == CardMetrics.sliderRange.lowerBound)
        #expect(widths.last == CardMetrics.sliderRange.upperBound)
        #expect(widths[1] - widths[0] == widths[2] - widths[1])
        #expect(widths.map(CardMetrics.recommendedName(forWidth:)) == ["Small", "Medium", "Large"])
        #expect(CardMetrics.recommendedName(forWidth: 170) == nil)
    }

    @Test("a width saved by the older build, between the old sizes, still resolves to a card")
    func olderWidths_stillResolve() {
        #expect(CardMetrics.widthRange.contains(150))
        #expect(CardMetrics.dimensions(width: 180).height == 160)
    }
}
