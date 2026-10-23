// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Reports the window a SwiftUI view is hosted in. The window is only known once the view is in the hierarchy.
struct HostWindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onChange(view?.window) }
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        DispatchQueue.main.async { [weak view] in onChange(view?.window) }
    }
}
