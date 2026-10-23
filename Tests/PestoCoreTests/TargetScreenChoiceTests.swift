// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Which display Pesto's windows use")
struct TargetScreenChoiceTests {
    private let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test("the display of the app being pasted into wins over the pointer")
    func whenTheTargetIsOnTheLeft_thenLeftEvenIfThePointerIsOnTheRight() {
        let index = TargetScreenChoice.index(
            windowCenter: CGPoint(x: 700, y: 400), pointer: CGPoint(x: 2000, y: 500), screenFrames: [left, right]
        )

        #expect(index == 0)
    }

    @Test("with no window to go by, the display under the pointer")
    func whenNoWindow_thenThePointer() {
        let index = TargetScreenChoice.index(
            windowCenter: nil, pointer: CGPoint(x: 2000, y: 500), screenFrames: [left, right]
        )

        #expect(index == 1)
    }

    @Test("a window centered outside every display, and a pointer outside too, fall back to the first display")
    func whenNothingMatches_thenTheFirst() {
        let index = TargetScreenChoice.index(
            windowCenter: CGPoint(x: -5000, y: 0), pointer: CGPoint(x: -5000, y: 0), screenFrames: [left, right]
        )

        #expect(index == 0)
    }

    @Test("no displays means no answer")
    func whenNoScreens_thenNil() {
        #expect(TargetScreenChoice.index(windowCenter: nil, pointer: .zero, screenFrames: []) == nil)
    }
}
