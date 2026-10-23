// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Opens the system colour panel for the accent's custom swatch and reports each colour the person picks as hex.
@MainActor
final class AccentColorPanel: NSObject {
    static let shared = AccentColorPanel()

    private var onChange: ((String) -> Void)?

    func show(current: Color, onChange: @escaping (String) -> Void) {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = false
        panel.color = NSColor(current)
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Puts the panel away and cuts it loose from the swatch, so it neither stays open after a preset is chosen nor
    /// goes on changing the accent when someone uses it for something else.
    func close() {
        let panel = NSColorPanel.shared
        guard onChange != nil || panel.isVisible else { return }
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
        onChange = nil
    }

    @objc
    private func colorChanged(_ panel: NSColorPanel) {
        if let hex = Color(nsColor: panel.color).toHex() { onChange?(hex) }
    }
}
