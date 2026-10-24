// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// Small floating "Press ⌘V to paste" toast — Tier 3 paste UX.
///
/// Non-modal, non-activating, auto-dismisses after 2.5 s with a 0.5 s fade.
/// Created fresh each time `ToastWindowController.show()` is called.
private struct ToastView: View {
    let toast: StatusToast
    let onClick: (() -> Void)?
    var holds = false
    @State private var opacity: Double = 0

    private var symbolName: String {
        switch toast {
        case .manualPaste: toast.isClickable ? "hand.point.up.left" : "keyboard"
        case .updatesUnavailable: "arrow.triangle.2.circlepath"
        case .upToDate: "checkmark.circle"
        case .filesGone: "doc.badge.clock"
        }
    }

    private var message: LocalizedStringKey {
        switch toast {
        case .manualPaste: toast.isClickable ? "Auto-paste is off. Click to turn it on." : "Press ⌘V to paste"
        case .updatesUnavailable: "This build does not check for updates."
        case .upToDate: "You\u{2019}re up to date."
        case .filesGone: "Nothing pasted: those files were moved or deleted."
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .pestoQuiet()
                .accessibilityHidden(true)
            Text(message)
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(.primary)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Card material like the hover card, at 92%, so the text holds 4.5:1 over a white or a black window behind it.
        .background {
            let shape = RoundedRectangle(cornerRadius: 10)
            shape.fill(Color.opaqueSurface.opacity(0.92)).adaptiveMaterialBackground(in: shape)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.14), lineWidth: 1))
        .opacity(opacity)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onClick?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(toast.isClickable ? .isButton : [])
        .accessibilityIdentifier(AccessibilityID.toast)
        .onAppear {
            withAnimation(Motion.animation(.easeIn(duration: 0.15))) { opacity = 1 }
            guard !holds else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + toast.visibleSeconds - 0.6) {
                withAnimation(Motion.animation(.easeOut(duration: 0.5))) { opacity = 0 }
            }
        }
    }
}

/// Manages the lifecycle of a toast panel.
@MainActor
final class ToastWindowController {
    private var panel: NSPanel?
    /// Task-based dismissal so the cancellable work runs on the main actor
    /// without requiring DispatchWorkItem (whose block is @Sendable, not @MainActor).
    private var dismissTask: Task<Void, Never>?

    /// Set once the longer text has been shown, so the explanation appears once per launch.
    private(set) var hasExplainedAutoPaste = false

    func show(_ toast: ManualPasteToast = .pressCommandV, onClick: (() -> Void)? = nil) {
        if toast == .autoPasteIsOff { hasExplainedAutoPaste = true }
        show(.manualPaste(toast), onClick: onClick)
    }

    /// `anchor` is the menu bar icon's frame in screen coordinates (nil when the icon is hidden); a notice about a
    /// menu bar action appears under it.
    func show(_ toast: StatusToast, anchor: NSRect? = nil, holds: Bool = false, onClick: (() -> Void)? = nil) {
        dismissExisting()

        let screen = TargetScreen.current() ?? NSScreen.main
        let hostingView = SafeHostingView(pesto: ToastView(toast: toast, onClick: onClick, holds: holds))
        // The text sets the width (a fixed width cut "This build does not check for updates." at larger text sizes).
        let fit = hostingView.fittingSize
        let widest = max(220, (screen?.visibleFrame.width ?? 800) - 48)
        let size = NSSize(width: min(max(fit.width, 220), widest), height: max(fit.height, 44))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = !toast.isClickable
        // Without these VoiceOver announces a borderless panel as "system dialog, group" (as for the shelf).
        panel.setAccessibilityRole(.window)
        panel.setAccessibilitySubrole(.floatingWindow)
        panel.setAccessibilityLabel(String(localized: "Pesto notice"))
        panel.contentView = hostingView

        if let screen {
            panel.setFrameOrigin(ToastPlacement.origin(
                for: toast.placement, size: size, visibleFrame: screen.visibleFrame, screenFrame: screen.frame,
                anchor: anchor
            ))
        }

        panel.orderFront(nil)
        self.panel = panel

        guard !holds else { return }
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(toast.visibleSeconds))
            self?.dismissExisting()
        }
    }

    private func dismissExisting() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
