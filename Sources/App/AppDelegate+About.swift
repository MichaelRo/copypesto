// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension AppDelegate {
    /// Pesto's own About window, in the look of the website and the first-run screen. One at a time: asking again
    /// raises
    /// it. Opened from the menu bar and from Settings → General.
    func openAboutWindow() {
        if let existing = aboutWindow {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AboutView.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The delegate owns this window; the default (true) makes AppKit release it on close as well, and the second
        // release crashes in the next display cycle (NSTouchBarFinder, macOS 27).
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(AccessibilityID.aboutWindow)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "About Pesto")
        window.isMovableByWindowBackground = true
        window.center()
        let hosting = SafeHostingView(pesto: AboutView().environment(appState).environment(
            \.shelfActions,
            appState.asShelfActions
        ).background(
            Button("Close") { [weak window] in window?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        ))
        hosting.setAccessibilityLabel(String(localized: "About Pesto"))
        window.contentView = hosting
        aboutWindow = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.aboutWindow = nil
                self?.updateActivationPolicy()
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
