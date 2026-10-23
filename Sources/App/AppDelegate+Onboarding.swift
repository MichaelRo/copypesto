// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftUI

extension AppDelegate {
    func applyOnboardingGate() {
        if AccessibilityAccess.isTrusted, AppDefaults.store.value(for: Setting.declinedAutoPaste) {
            AppDefaults.store.set(false, for: Setting.declinedAutoPaste)
        }
        switch OnboardingGate.action(
            keyAvailable: BlobEncryption.isKeyAvailable,
            hasOnboarded: AppDefaults.store.value(for: Setting.hasOnboarded),
            accessibilityTrusted: AccessibilityAccess.isTrusted,
            declinedAutoPaste: AppDefaults.store.value(for: Setting.declinedAutoPaste)
        ) {
        case .showOnboarding:
            showOnboarding()
        case .promptForAccessibility:
            // Already onboarded but AX was revoked / CDHash changed: surface the system prompt without forcing
            // them back through the full onboarding flow.
            promptForAccessibilityOncePerVersion()
        case .nothing:
            break
        }
    }

    func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let onboarding = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        onboarding.isReleasedWhenClosed = false
        onboarding.identifier = NSUserInterfaceItemIdentifier(AccessibilityID.onboardingWindow)
        onboarding.titlebarAppearsTransparent = true
        onboarding.titleVisibility = .hidden
        // `titleVisibility = .hidden` also leaves the window with no accessible name; setting `title`
        // still gives VoiceOver one and stays invisible on screen.
        onboarding.title = String(localized: "Welcome to Pesto")
        onboarding.isMovableByWindowBackground = true
        onboarding.center()
        let onboardingHosting = SafeHostingView(pesto: OnboardingView(appState: appState))
        // The window's title and the SwiftUI root's own accessibilityLabel each satisfy their own
        // level; the hosting view sits between them as its own AX node and needs a label too — same
        // pattern as OverlayWindowController's hostingView.
        onboardingHosting.setAccessibilityLabel(String(localized: "Welcome to Pesto"))
        onboarding.contentView = onboardingHosting
        onboardingWindow = onboarding
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: onboarding, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onboardingWindow = nil
                self?.updateActivationPolicy()
            }
        }
        NSApp.setActivationPolicy(.regular)
        onboarding.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
