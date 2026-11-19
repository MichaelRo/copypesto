// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
@testable import PestoMobile

@Suite("Arrow keys move the focused card through the grid")
struct GridFocusMoveTests {
    @Test("up and down move a whole row; nothing past the first or last row")
    func whenUpOrDown_thenARowAtATime() {
        #expect(GridFocusMove.target(from: 4, count: 9, columns: 3, moving: .up) == 1)
        #expect(GridFocusMove.target(from: 4, count: 9, columns: 3, moving: .down) == 7)
        #expect(GridFocusMove.target(from: 1, count: 9, columns: 3, moving: .up) == nil)
        #expect(GridFocusMove.target(from: 5, count: 7, columns: 3, moving: .down) == nil, "row below is short")
    }

    @Test("back and forward stay in their row")
    func whenSideways_thenWithinTheRow() {
        #expect(GridFocusMove.target(from: 4, count: 9, columns: 3, moving: .back) == 3)
        #expect(GridFocusMove.target(from: 3, count: 9, columns: 3, moving: .back) == nil)
        #expect(GridFocusMove.target(from: 4, count: 9, columns: 3, moving: .forward) == 5)
        #expect(GridFocusMove.target(from: 5, count: 9, columns: 3, moving: .forward) == nil)
        #expect(GridFocusMove.target(from: 7, count: 8, columns: 3, moving: .forward) == nil, "the last card")
    }

    @Test("left and right follow the layout direction; other keys are not moves")
    func whenRightToLeft_thenLeftMovesForward() {
        #expect(GridFocusMove.direction(of: .leftArrow, layout: .leftToRight) == .back)
        #expect(GridFocusMove.direction(of: .leftArrow, layout: .rightToLeft) == .forward)
        #expect(GridFocusMove.direction(of: .rightArrow, layout: .rightToLeft) == .back)
        #expect(GridFocusMove.direction(of: .return, layout: .leftToRight) == nil)
    }

    @Test("an empty grid or a stale index moves nowhere")
    func whenNothingToMoveTo_thenNil() {
        #expect(GridFocusMove.target(from: 0, count: 0, columns: 2, moving: .down) == nil)
        #expect(GridFocusMove.target(from: 9, count: 3, columns: 2, moving: .up) == nil)
    }
}
