// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// Manages the always-on-top floating clipboard panel.
///
/// Unlike the transient overlay (slide-up shelf), this panel is resizable, movable, and
/// persists across app-switch events. Items are copied to the clipboard on tap/Return;
/// no auto-paste fires. The panel position is saved to UserDefaults between sessions.
@MainActor
final class PinnedWindowController: NSObject {
    private var panel: NSPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if appState.isPinnedWindowVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil { buildPanel() }
        restoreFrame()
        panel?.makeKeyAndOrderFront(nil)
        appState.isPinnedWindowVisible = true
        appState.checkAndApplyBiometricLock()
    }

    func hide() {
        saveFrame()
        panel?.orderOut(nil)
        appState.isPinnedWindowVisible = false
    }

    // MARK: - Private

    private func buildPanel() {
        let p = NSPanel(
            contentRect: defaultFrame(),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // .nonactivatingPanel + becomesKeyOnlyIfNeeded keep the previously focused
        // app frontmost when the user clicks the pinned panel. Without this, clicking
        // a card would activate Pesto and the auto-paste flow would have no target
        // app to restore focus to. NSPanel does still receive mouse / keyboard events.
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.minSize = NSSize(width: 600, height: 240)
        p.setAccessibilityIdentifier(AccessibilityID.pinnedPanel)
        // titleVisibility = .hidden hides the title but also leaves the panel with no accessible name.
        p.setAccessibilityLabel(String(localized: "Floating window"))
        p.delegate = self

        let root = PinnedWindowRootView()
            .environment(appState)
            .environment(\.shelfActions, appState.asShelfActions)
        let hosting = SafeHostingView(pesto: root)
        hosting.focusRingType = .none
        // The panel's own label and the SwiftUI root's own accessibilityLabel each satisfy their
        // own level; the hosting view sits between them as its own AX node and needs a label too.
        hosting.setAccessibilityLabel(String(localized: "Floating window"))
        p.contentView = hosting
        panel = p
    }

    private func defaultFrame() -> NSRect {
        let screen = TargetScreen.current() ?? NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 900
        let height: CGFloat = 320
        let x = (screen.frame.width - width) / 2 + screen.frame.minX
        let y = screen.visibleFrame.minY + 60
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func restoreFrame() {
        guard let panel else { return }
        let str = AppDefaults.store.value(for: Setting.pinnedWindowFrame)
        let rect = NSRectFromString(str)
        if !str.isEmpty, !rect.isEmpty, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
            let target = (TargetScreen.current() ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            panel.setFrame(
                FloatingWindowPlacement.frame(
                    saved: rect,
                    displays: NSScreen.screens.map(\.visibleFrame),
                    target: target
                ),
                display: false
            )
        } else {
            panel.setFrame(defaultFrame(), display: false)
        }
    }

    private func saveFrame() {
        if let frame = panel?.frame {
            AppDefaults.store.set(NSStringFromRect(frame), for: Setting.pinnedWindowFrame)
        }
    }
}

extension PinnedWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        appState.isPinnedWindowVisible = false
        saveFrame()
    }
}
