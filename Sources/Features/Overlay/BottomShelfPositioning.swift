// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import PestoCore

enum BottomShelfPositioning {
    /// The panel's height: the card row and its fixed chrome, plus whatever banners the shelf measured above the
    /// command bar (`AppState.shelfBannerHeight`).
    static func overlayHeight(banners: CGFloat = 0) -> CGFloat {
        let defaults = AppDefaults.store
        let size = CardSize.dimensions(
            sizeRaw: defaults.value(for: Setting.cardSize), customWidth: defaults.value(for: Setting.cardWidth)
        )
        return ShelfHeight.height(forCardHeight: size.height) + max(0, banners)
    }

    static var position: ShelfPosition {
        ShelfPosition(stored: AppDefaults.store.value(for: Setting.shelfPosition))
    }

    /// The shelf's rect on the display of the app being pasted into (`TargetScreen`): the full usable width, resting on
    /// the Dock or
    /// hanging from the menu bar, whichever the person chose.
    @MainActor
    static func frame(for screen: NSScreen? = nil, banners: CGFloat = 0) -> NSRect {
        guard let targetScreen = screen ?? TargetScreen.current() ?? NSScreen.main ?? NSScreen.screens.first else {
            return .zero
        }
        return position.frame(
            on: ShelfPosition.Screen(
                frame: targetScreen.frame,
                visibleFrame: targetScreen.visibleFrame,
                safeAreaTop: targetScreen.safeAreaInsets.top
            ),
            height: overlayHeight(banners: banners)
        )
    }
}
