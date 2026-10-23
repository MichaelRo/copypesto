// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("How large the Quick Look preview opens")
struct QuickLookPanelSizingTests {
    private let screen = CGRect(x: 0, y: 70, width: 1600, height: 900)

    @Test("a preview larger than its share of the display is shrunk to that share and centred")
    func whenTooLarge_thenShrunkAndCentred() {
        let frame = QuickLookPanelSizing.frame(preferred: CGSize(width: 1500, height: 880), in: screen)
        #expect(abs(frame.width - 880) < 0.001)
        #expect(abs(frame.height - 585) < 0.001)
        #expect(abs(frame.midX - screen.midX) < 0.001)
        #expect(abs(frame.midY - screen.midY) < 0.001)
    }

    @Test("a small preview keeps its own size")
    func whenSmall_thenUnchanged() {
        let frame = QuickLookPanelSizing.frame(preferred: CGSize(width: 400, height: 300), in: screen)
        #expect(frame.size == CGSize(width: 400, height: 300))
    }
}
