// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

/// Positions and animates a compact 5-item clipboard mini-panel near the cursor insertion point.
///
/// The panel is a non-activating `NSPanel`. It dismisses on item selection, Escape, or any
/// click outside its frame (via a global mouse-down monitor — same approach as the main overlay).
@MainActor
final class QuickMenuWindowController {
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private let appState: AppState

    private static let escapeKeyCode: UInt16 = 53
    private static let shownCards = 5

    init(appState: AppState) {
        self.appState = appState
    }

    func show(
        near cursorRect: CGRect,
        onSelect: @escaping (PasteCoordinator.PayloadKind) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // Hide any previously orphaned panel before creating a new one.
        hide()

        let panel = makePanel(onSelect: onSelect, onDismiss: onDismiss)
        self.panel = panel

        let frame = positionedFrame(near: cursorRect)
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        guard let layer = panel.contentView?.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = -20

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0

        let group = CAAnimationGroup()
        group.animations = PanelMotion.slides(reduceMotion: PanelMotion.systemReduceMotion) ? [slide, fade] : [fade]
        group.duration = 0.2
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0.75, 0.35, 1.0)
        group.fillMode = .backwards
        group.isRemovedOnCompletion = true

        layer.add(group, forKey: "showQuickMenu")
        installClickMonitor(onDismiss: onDismiss)
        installKeyMonitor(onDismiss: onDismiss)
    }

    func hide() {
        removeClickMonitor()
        removeKeyMonitor()
        guard let panel else { return }
        let panelRef = panel
        self.panel = nil

        guard let layer = panelRef.contentView?.layer else {
            panelRef.orderOut(nil)
            return
        }

        // Set model opacity only — do NOT set a non-identity layer.transform here.
        // AppKit creates _NSWindowTransformAnimation when the layer transform diverges from
        // the window frame; on macOS 26 that internal animation crashes (SIGSEGV) in its
        // dealloc when its autorelease pool is drained during this same CA transaction flush.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()

        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = 0
        slide.toValue = -20 // explicit toValue; model transform stays identity

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        // opacity toValue is the model value (0)

        let group = CAAnimationGroup()
        group.animations = PanelMotion.slides(reduceMotion: PanelMotion.systemReduceMotion) ? [slide, fade] : [fade]
        group.duration = 0.15
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // fillMode = .forwards holds the final visual state until we remove the animation
        // explicitly in the completion block, preventing a snap-back before orderOut.
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                layer.removeAnimation(forKey: "hideQuickMenu")
                panelRef.orderOut(nil)
                // Reset layer so it's clean if the panel is reused.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.opacity = 1
                layer.transform = CATransform3DIdentity
                CATransaction.commit()
            }
        }
        layer.add(group, forKey: "hideQuickMenu")
        CATransaction.commit()
    }

    // MARK: - Private

    private func installClickMonitor(onDismiss: @escaping () -> Void) {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            guard let frame = self.panel?.frame, !frame.contains(mouse) else { return }
            Task { @MainActor [weak self] in
                self?.hide()
                onDismiss()
            }
        }
    }

    private func installKeyMonitor(onDismiss: @escaping () -> Void) {
        guard keyMonitor == nil else { return }
        // The panel is non-activating, so Escape goes to the app being typed into; only a global monitor sees it.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return }
            Task { @MainActor [weak self] in
                self?.hide()
                onDismiss()
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func makePanel(
        onSelect: @escaping (PasteCoordinator.PayloadKind) -> Void,
        onDismiss: @escaping () -> Void
    )
    -> NSPanel {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.setAccessibilityIdentifier(AccessibilityID.quickMenuPanel)
        // titleVisibility = .hidden hides the title but also leaves the panel with no accessible name.
        p.setAccessibilityLabel(String(localized: "Quick menu"))
        p.isFloatingPanel = true
        p.level = .floating
        p.isMovableByWindowBackground = false
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.hasShadow = false
        p.backgroundColor = .clear

        let rootView = QuickMenuView(
            onSelect: onSelect,
            onDismiss: { [weak self] in
                self?.hide()
                onDismiss()
            }
        )
        .environment(appState)

        // The container must be injected by an ancestor of QuickMenuView: its own @Query reads the
        // environment above it, so applying it inside the view left the menu permanently empty.
        let content: AnyView = appState.historyContainer.map { AnyView(rootView.modelContainer($0)) }
            ?? AnyView(rootView)
        let hostingView = SafeHostingView(pesto: content)
        // The panel's own label and the SwiftUI root's own accessibilityLabel each satisfy their
        // own level; the hosting view sits between them as its own AX node and needs a label too.
        hostingView.setAccessibilityLabel(String(localized: "Quick menu"))
        p.contentView = hostingView
        return p
    }

    private func positionedFrame(near cursorRect: CGRect) -> CGRect {
        let cursorScreen = NSScreen.screens.first { $0.frame.intersects(cursorRect) } ?? NSScreen.main
        let screenFrame = cursorScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8
        let cardSize = CardSize.dimensions(
            sizeRaw: AppDefaults.store.value(for: Setting.cardSize),
            customWidth: AppDefaults.store.value(for: Setting.cardWidth)
        )
        let panelSize = QuickMenuMetrics.panelSize(
            cardSize: cardSize, cards: Self.shownCards, maxWidth: screenFrame.width - 16
        )
        let panelWidth = panelSize.width
        let panelHeight = panelSize.height

        var x = cursorRect.midX - panelWidth / 2
        var y = cursorRect.maxY + gap

        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - panelWidth - 8))

        if y + panelHeight > screenFrame.maxY {
            y = cursorRect.minY - panelHeight - gap
        }

        y = max(screenFrame.minY + 8, min(y, screenFrame.maxY - panelHeight - 8))

        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }
}
