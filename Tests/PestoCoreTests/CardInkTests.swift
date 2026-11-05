// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Card ink")
struct CardInkTests {
    private func fill(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) -> HexColorComponents {
        HexColorComponents(red: red, green: green, blue: blue, alpha: alpha)
    }

    @Test("white ink on dark fills and black ink on light ones")
    func whenFillExtremes_thenInkContrasts() {
        #expect(CardInk.forFill(fill(0, 0, 0), backdropIsDark: true) == .white)
        #expect(CardInk.forFill(fill(1, 1, 1), backdropIsDark: true) == .black)
        #expect(CardInk.forFill(fill(0, 0, 1), backdropIsDark: true) == .white)
        #expect(CardInk.forFill(fill(1, 1, 0), backdropIsDark: true) == .black)
    }

    @Test("every grey gets whichever ink reads better, never the weaker one")
    func whenAnyFill_thenInkContrastIsTheBetterOfTheTwo() {
        for step in 0...20 {
            let value = Double(step) / 20
            let color = fill(value, value, value)
            let luminance = color.luminance
            let white = 1.05 / (luminance + 0.05)
            let black = (luminance + 0.05) / 0.05
            #expect(CardInk.forFill(color, backdropIsDark: true) == (white >= black ? .white : .black))
        }
    }

    @Test("a see-through fill is judged over what is behind it")
    func whenTranslucent_thenBackdropDecides() {
        let faint = fill(0, 0, 0, alpha: 0.1)
        #expect(CardInk.forFill(faint, backdropIsDark: false) == .black)
        #expect(CardInk.forFill(faint, backdropIsDark: true) == .white)
    }

    @Test("the hex is set at 26 points up to nine characters and smaller for a function like rgba()")
    func whenLabelLength_thenPoints() {
        #expect(CardInk.labelPoints(forLength: 7) == 26)
        #expect(CardInk.labelPoints(forLength: 9) == 26)
        #expect(CardInk.labelPoints(forLength: 10) == 15)
        #expect(CardInk.labelPoints(forLength: 40) == 15)
    }
}
