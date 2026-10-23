// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftData
import SwiftUI

// MARK: - Settings window

@MainActor
extension AppDelegate {
    func openSettingsWindow() {
        Self.logger.notice("[settings] open requested")

        let overlayRef = overlayWindowController?.overlayWindow

        // If the Settings window is already on screen, just raise it.
        if let existing = settingsWindow ?? NSApp.windows
            .first(where: { Self.isSettingsWindow($0, overlay: overlayRef) })
        {
            Self.logger.notice("[settings] existing window found — raising")
            NSApp.setActivationPolicy(.regular)
            bringToFront(existing)
            if settingsWindowObserver == nil { attachSettingsCloseObserver(to: existing) }
            return
        }

        // Create the Settings window directly via SafeHostingView. This bypasses
        // NSApp.sendAction("showSettingsWindow:") which requires a primary SwiftUI scene
        // (WindowGroup or MenuBarExtra) in the responder chain — absent on macOS 26 when
        // the app only has a Settings { } scene.
        let win = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The delegate owns this window; the default (true) makes AppKit release it on close as well, and
        // the second release crashes in the next display cycle (NSTouchBarFinder, macOS 27).
        win.isReleasedWhenClosed = false
        win.title = String(localized: "Settings")
        win.standardWindowButton(.zoomButton)?.isEnabled = false
        win.identifier = NSUserInterfaceItemIdentifier(AccessibilityID.settingsWindow)
        win.center()
        let rootView: AnyView = appState.historyContainer.map {
            AnyView(SettingsView().environment(appState).environment(\.shelfActions, appState.asShelfActions)
                .modelContainer($0))
        } ?? AnyView(SettingsView().environment(appState).environment(\.shelfActions, appState.asShelfActions))
        win.contentView = SafeHostingView(pesto: rootView)

        if let obs = settingsWindowObserver {
            NotificationCenter.default.removeObserver(obs)
            settingsWindowObserver = nil
        }

        restoreSettingsFrame(win)
        settingsWindow = win // retain so the window isn't deallocated after this scope
        // Change activation policy AFTER the window is ready to show, not before.
        // This ensures .regular doesn't leak if window creation somehow fails.
        NSApp.setActivationPolicy(.regular)
        bringToFront(win)
        attachSettingsCloseObserver(to: win)
        Self.logger.notice("[settings] window created and shown")
    }

    /// Opened from the shelf (a non-activating panel), another app is still the active one and macOS refuses a
    /// cooperative `activate()`, which left Settings behind it. Activating with ignoringOtherApps brings it to front
    /// immediately; asking Launch Services is the resilient fallback if the process has not become active.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !NSApp.isActive else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func attachSettingsCloseObserver(to win: NSWindow) {
        settingsWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                Self.logger.notice("[settings] window closed — reverting to .accessory")
                self.saveSettingsFrame(win)
                AccentColorPanel.shared.close()
                self.settingsWindow = nil
                self.updateActivationPolicy()
                if let obs = self.settingsWindowObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self.settingsWindowObserver = nil
                }
            }
        }
    }

    /// True when `window` is the Settings window — matched by the stable identifier
    /// `net.copypesto.pesto.settings` set in `openSettingsWindow()`. Title-based matching is
    /// fragile under localization and can accidentally match third-party windows.
    private static func isSettingsWindow(_ window: NSWindow, overlay: NSWindow?) -> Bool {
        guard window !== overlay else { return false }
        return window.identifier?.rawValue == AccessibilityID.settingsWindow
    }

    private func restoreSettingsFrame(_ window: NSWindow) {
        let str = AppDefaults.store.value(for: Setting.settingsWindowFrame)
        // The redesigned panes open with a header and want room: a frame saved by an older, smaller window is ignored,
        // and one saved by an older, taller window is cut to a height that suits the panes.
        if !str.isEmpty,
           let frame = SettingsWindowFrame.restored(
               saved: NSRectFromString(str), displays: NSScreen.screens.map(\.visibleFrame)
           )
        {
            window.setFrame(frame, display: true)
        } else {
            // Center at a comfortable default size.
            window.setContentSize(NSSize(width: 800, height: 720))
            window.center()
        }
    }

    private func saveSettingsFrame(_ window: NSWindow) {
        AppDefaults.store.set(NSStringFromRect(window.frame), for: Setting.settingsWindowFrame)
    }
}
