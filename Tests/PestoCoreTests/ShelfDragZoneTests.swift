// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("The part of the shelf that stays live while a clip is dragged out")
struct ShelfDragZoneTests {
    private let panel = CGRect(x: 0, y: 0, width: 1500, height: 300)

    @Test("the command bar strip at the top of the panel stays live, so a clip can be dropped on a collection chip")
    func whenOverTheCommandBar_thenLive() {
        #expect(ShelfDragZone.isOverDropZone(pointer: CGPoint(x: 400, y: 290), panelFrame: panel))
        #expect(ShelfDragZone.isOverDropZone(
            pointer: CGPoint(x: 400, y: 300 - ShelfHeight.commandBlock + 1),
            panelFrame: panel
        ))
    }

    @Test("everywhere else on the panel the shelf lets the drag through to the app behind it")
    func whenOverTheCards_thenClickThrough() {
        #expect(!ShelfDragZone.isOverDropZone(pointer: CGPoint(x: 400, y: 150), panelFrame: panel))
        #expect(!ShelfDragZone.isOverDropZone(pointer: CGPoint(x: 400, y: 5), panelFrame: panel))
        #expect(!ShelfDragZone.isOverDropZone(
            pointer: CGPoint(x: 400, y: 300 - ShelfHeight.commandBlock - 1),
            panelFrame: panel
        ))
    }

    @Test("a pointer off the panel is never over its drop zone")
    func whenOffThePanel_thenNotLive() {
        #expect(!ShelfDragZone.isOverDropZone(pointer: CGPoint(x: 1600, y: 290), panelFrame: panel))
        #expect(!ShelfDragZone.isOverDropZone(pointer: CGPoint(x: 400, y: 400), panelFrame: panel))
    }
}
