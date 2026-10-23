// SPDX-License-Identifier: MIT
import CoreGraphics

public struct WindowSnapshot: Sendable, Equatable {
    public var ownerPID: Int32
    public var layer: Int
    public var isOnScreen: Bool
    public var width: Double
    public var height: Double
    public var alpha: Double

    public init(ownerPID: Int32, layer: Int, isOnScreen: Bool, width: Double, height: Double, alpha: Double) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.width = width
        self.height = height
        self.alpha = alpha
    }
}

/// Chrome, Edge, Brave and the other Chromium browsers draw a small bar ("… is sharing your screen · Stop sharing")
/// at the status-window level while a page shares the screen or a window, and Firefox draws its sharing indicator bar
/// at the floating-window level; an idle browser has no such window. It is the one signal of a browser share that
/// needs no permission: owner, layer and size, never a title (recorded in `Tests/PestoCoreTests/Fixtures`, ADR 0003).
/// Safari and a share of one tab are not recognised.
public enum BrowserShareSignature {
    private static let chromiumBundleIDPrefixes = [
        "com.google.chrome", "com.microsoft.edgemac", "com.brave.browser", "company.thebrowser.browser",
        "com.vivaldi.vivaldi", "com.operasoftware.opera", "org.chromium.chromium"
    ]
    private static let firefoxBundleIDPrefixes = [
        "org.mozilla.firefox", "org.mozilla.nightly"
    ]

    private static let statusWindowLayer = Int(CGWindowLevelForKey(.statusWindow))
    private static let floatingWindowLayer = Int(CGWindowLevelForKey(.floatingWindow))
    private static let heights = 30.0...120.0
    private static let widths = 200.0...1000.0

    public static func isSharing(windows: [WindowSnapshot], bundleID: (Int32) -> String?) -> Bool {
        windows.contains { window in
            guard window.isOnScreen,
                  heights.contains(window.height), widths.contains(window.width),
                  let id = bundleID(window.ownerPID)?.lowercased() else { return false }
            if window.layer == statusWindowLayer {
                return chromiumBundleIDPrefixes.contains { id.hasPrefix($0) }
            }
            if window.layer == floatingWindowLayer {
                return firefoxBundleIDPrefixes.contains { id.hasPrefix($0) }
            }
            return false
        }
    }

    /// The windows on screen now. Reading owner, layer and bounds needs no Screen Recording permission.
    public nonisolated static func onScreenWindows() -> [WindowSnapshot] {
        let raw = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        return raw.map { window in
            let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return WindowSnapshot(
                ownerPID: Int32(truncatingIfNeeded: window[kCGWindowOwnerPID as String] as? Int ?? 0),
                layer: window[kCGWindowLayer as String] as? Int ?? 0,
                isOnScreen: window[kCGWindowIsOnscreen as String] as? Bool ?? true,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0,
                alpha: window[kCGWindowAlpha as String] as? Double ?? 1
            )
        }
    }
}
