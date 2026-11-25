// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("How big the keyboard's search page is")
struct KeyboardSearchMetricsTests {
    @Test("results take one row on Small and Medium and two on Large, and one in landscape and on iPad")
    func whenSized_thenResultRowsFollow() {
        #expect(KeyboardSearchMetrics.resultRows(size: .small, isRegular: false, isLandscape: false) == 1)
        #expect(KeyboardSearchMetrics.resultRows(size: .medium, isRegular: false, isLandscape: false) == 1)
        #expect(KeyboardSearchMetrics.resultRows(size: .large, isRegular: false, isLandscape: false) == 2)
        #expect(KeyboardSearchMetrics.resultRows(size: .large, isRegular: false, isLandscape: true) == 1)
        #expect(KeyboardSearchMetrics.resultRows(size: .large, isRegular: true, isLandscape: false) == 1)
    }

    @Test("result cards are never smaller than 140 by 64, and iPad's are larger")
    func whenSized_thenCardsStayReadable() {
        for size in KeyboardSize.allCases {
            let card = KeyboardSearchMetrics.resultCard(size: size, isRegular: false)
            #expect(card.width >= 140 && card.height >= 64)
            #expect(KeyboardSearchMetrics.resultCard(size: size, isRegular: true).height > card.height)
        }
    }

    @Test("keys are iOS's height, and a four-row script fits the same letter area")
    func whenKeys_thenSystemMetrics() {
        #expect(KeyboardSearchMetrics.keyHeight(rowCount: 3, isRegular: false, isLandscape: false) == 42)
        #expect(KeyboardSearchMetrics.keyHeight(rowCount: 3, isRegular: true, isLandscape: false) == 52)
        let four = KeyboardSearchMetrics.keyHeight(rowCount: 4, isRegular: false, isLandscape: false)
        let area = KeyboardSearchMetrics.letterAreaHeight(isRegular: false, isLandscape: false)
        let gap = KeyboardSearchMetrics.rowGap(isRegular: false, isLandscape: false)
        #expect(four * 4 + gap * 3 <= area + 0.5)
        #expect(four >= 28)
    }

    @Test("the page grows with the result rows and stays within half a phone's height")
    func whenTotalled_thenBounded() {
        let small = KeyboardSearchMetrics.totalHeight(size: .small, isRegular: false, isLandscape: false)
        let large = KeyboardSearchMetrics.totalHeight(size: .large, isRegular: false, isLandscape: false)
        #expect(large > small)
        #expect(small >= 284)
        #expect(large <= 450)
        #expect(KeyboardSearchMetrics.totalHeight(size: .large, isRegular: false, isLandscape: true) <= 290)
        #expect(
            KeyboardLayout.totalHeight(size: .medium, isRegular: false, isLandscape: false, isSearching: true)
                == KeyboardSearchMetrics.totalHeight(size: .medium, isRegular: false, isLandscape: false)
        )
    }
}
