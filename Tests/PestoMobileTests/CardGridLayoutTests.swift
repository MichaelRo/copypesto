// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoMobile

@Suite("How many cards a row holds and how much text a card shows")
struct CardGridLayoutTests {
    @Test("an iPhone shows two columns in portrait and three in landscape")
    func whenIPhone_thenTwoOrThreeColumns() {
        #expect(CardGridLayout.columnCount(width: 370, isAccessibilitySize: false) == 2)
        #expect(CardGridLayout.columnCount(width: 718, isAccessibilitySize: false) == 3)
    }

    @Test("a narrow width never drops below two columns, an iPad grid adds columns as it widens")
    func whenWidthChanges_thenColumnsFollow() {
        #expect(CardGridLayout.columnCount(width: 300, isAccessibilitySize: false) == 2)
        #expect(CardGridLayout.columnCount(width: 828, isAccessibilitySize: false) == 4)
        #expect(CardGridLayout.columnCount(width: 1140, isAccessibilitySize: false) == 5)
        #expect(CardGridLayout.columnCount(width: 0, isAccessibilitySize: false) == 2)
    }

    @Test("an accessibility text size gives one column at any width")
    func whenAccessibilitySize_thenOneColumn() {
        #expect(CardGridLayout.columnCount(width: 370, isAccessibilitySize: true) == 1)
        #expect(CardGridLayout.columnCount(width: 1140, isAccessibilitySize: true) == 1)
    }

    @Test("cards share the width after the gaps, and keep the Mac card's 10 by 9 shape")
    func whenSized_thenCardsFillTheRow() {
        let width = CardGridLayout.cardWidth(rowWidth: 370, columns: 2)
        #expect(width == 179)
        #expect(abs(CardGridLayout.cardHeight(forWidth: 200) - 180) < 0.001)
    }

    @Test("a card shows as many whole lines as fit, and at least one")
    func whenTextIsLaidOut_thenOnlyWholeLinesShow() {
        #expect(CardGridLayout.lineLimit(height: 100, lineHeight: 20) == 5)
        #expect(CardGridLayout.lineLimit(height: 99, lineHeight: 20) == 4)
        #expect(CardGridLayout.lineLimit(height: 5, lineHeight: 20) == 1)
        #expect(CardGridLayout.lineLimit(height: 100, lineHeight: 0) == 1)
    }
}
