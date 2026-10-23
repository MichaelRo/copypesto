// SPDX-License-Identifier: MIT
import Foundation

/// Where a request to open the shelf came from. Only the shortcut opens the small menu at the cursor: it is the one
/// route where the person is typing in another app and asked for that app's clips. A menu item named "Open Shelf", a
/// link, a script or a Shortcut must open the shelf it names, whatever the frontmost app is doing.
public enum ShelfOpenSource: CaseIterable, Sendable {
    case hotkey
    case statusMenu
    case link
    case script
    case intent
    case internalRoute

    public var allowsQuickMenu: Bool {
        self == .hotkey
    }
}
