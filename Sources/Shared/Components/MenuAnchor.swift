// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Where a `PopUpMenuButton` opens its menu: the view behind the button.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
}

struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        anchor.view = view
    }
}
