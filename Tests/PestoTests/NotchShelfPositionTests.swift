// SPDX-License-Identifier: MIT
import CoreGraphics
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("NotchShelfPosition", .serialized)
    @MainActor
    final class NotchShelfPositionTests {
        @Test("underNotch shelf with safeAreaInsets.top = 38 hangs below notch even if visibleFrame reaches top")
        func whenSafeAreaTopIs38_thenUnderNotchShelfStaysBelowNotch() {
            let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
            let visibleWithHiddenMenuBar = CGRect(x: 0, y: 70, width: 1512, height: 912)
            let screen = ShelfPosition.Screen(
                frame: screenFrame,
                visibleFrame: visibleWithHiddenMenuBar,
                safeAreaTop: 38
            )

            let shelfFrame = ShelfPosition.underNotch.frame(on: screen, height: 250)
            #expect(shelfFrame.maxY == screenFrame.maxY - 38)
            #expect(shelfFrame.height == 250)
            #expect(shelfFrame.minY == screenFrame.maxY - 38 - 250)
        }
    }
}
