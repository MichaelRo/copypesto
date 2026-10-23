// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import PestoCore

/// The display Pesto's windows use: that of the app being pasted into (`TargetScreenChoice`). The frontmost app's
/// frontmost window is found from the window list, which needs no permission for the position of a window.
enum TargetScreen {
    @MainActor
    static func current() -> NSScreen? {
        let screens = NSScreen.screens
        let index = TargetScreenChoice.index(
            windowCenter: targetWindowCenter(),
            pointer: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame)
        )
        return index.map { screens[$0] }
    }

    @MainActor
    private static func targetWindowCenter() -> CGPoint? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
              as? [[String: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width > 50, bounds.height > 50 else { continue }
            let cocoa = ScreenCoordinates.cocoaRect(fromAX: bounds, primaryScreenHeight: primary.frame.height)
            return CGPoint(x: cocoa.midX, y: cocoa.midY)
        }
        return nil
    }
}
