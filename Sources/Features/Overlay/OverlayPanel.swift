// SPDX-License-Identifier: MIT
import AppKit
@preconcurrency import Quartz

/// Non-activating floating panel that hosts the clipboard shelf.
/// `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded = true` means clicking a card
/// does not steal focus from the frontmost app.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        setAccessibilityIdentifier(AccessibilityID.overlayPanel)
        // Without these VoiceOver announces a borderless panel as "system dialog, group".
        setAccessibilityRole(.window)
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel(String(localized: "Clipboard history"))
    }

    /// Allow keyboard events even though we're non-activating.
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Fallback Escape handler — fires when SwiftUI focus is absent (e.g. if the
    /// hosting view never grabbed first-responder status). The two-stage clear-then-
    /// dismiss logic lives in GridView.handleEscape; this path just force-dismisses.
    var onEscapeKey: (() -> Void)?

    override func cancelOperation(_: Any?) {
        onEscapeKey?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscapeKey?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Quick Look

    // swiftlint:disable implicitly_unwrapped_optional
    override func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_: QLPreviewPanel!) {}

    override func endPreviewPanelControl(_: QLPreviewPanel!) {}
    // swiftlint:enable implicitly_unwrapped_optional
}
