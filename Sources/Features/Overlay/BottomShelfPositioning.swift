// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import PestoCore

enum BottomShelfPositioning {
    static var overlayHeight: CGFloat {
        let defaults = AppDefaults.store
        let size = CardSize.dimensions(
            sizeRaw: defaults.value(for: Setting.cardSize), customWidth: defaults.value(for: Setting.cardWidth)
        )
        return ShelfHeight.height(forCardHeight: size.height)
    }

    static var position: ShelfPosition {
        ShelfPosition(stored: AppDefaults.store.value(for: Setting.shelfPosition))
    }

    /// The shelf's rect on the display of the app being pasted into (`TargetScreen`): the full usable width, resting on
    /// the Dock or
    /// hanging from the menu bar, whichever the person chose.
    @MainActor
    static func frame(for screen: NSScreen? = nil) -> NSRect {
        let targetScreen = screen ?? TargetScreen.current() ?? NSScreen.main ?? NSScreen.screens[0]
        return position.frame(
            on: ShelfPosition.Screen(
                frame: targetScreen.frame,
                visibleFrame: targetScreen.visibleFrame,
                safeAreaTop: targetScreen.safeAreaInsets.top
            ),
            height: overlayHeight
        )
    }
}
