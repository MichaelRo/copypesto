// SPDX-License-Identifier: MIT
import AppKit

enum PasteboardAccessSettings {
    static func open() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")
        let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        if let target = pane ?? privacy { NSWorkspace.shared.open(target) }
    }
}
