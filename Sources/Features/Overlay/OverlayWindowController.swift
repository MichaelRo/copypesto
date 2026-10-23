// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
@preconcurrency import Quartz
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: OverlayPanel
    var overlayWindow: NSWindow {
        panel
    }

    private let appState: AppState
    var onClickOutside: (() -> Void)?
    private var clickMonitor: Any?
    private var dragEndMonitor: Any?
    private var resignKeyObserver: (any NSObjectProtocol)?
    private var appActivateObserver: (any NSObjectProtocol)?
    private var isHiding = false
    private var dragClearanceTimer: Timer?
    /// Bumped by every show() so a hide animation that finishes after a re-show cannot order the panel out.
    private var showGeneration = 0
    private var pendingCompletion: (() -> Void)?
    /// Polls Accessibility trust state while the overlay is visible so the "Grant access"
    /// banner disappears within ~1 s of the user granting permission in System Settings,
    /// without requiring a Pesto restart. There's no public macOS API to observe AX grants.
    /// DispatchSourceTimer (not Foundation.Timer): a runloop Timer stops firing when the runloop leaves the default
    /// mode.
    private var axPollTimer: (any DispatchSourceTimer)?

    init(appState: AppState) {
        self.appState = appState
        panel = OverlayPanel()
        panel.title = String(localized: "Pesto clipboard history")
        panel.setAccessibilityLabel(String(localized: "Pesto clipboard history"))

        let rootView = OverlayRootView()
            .environment(appState)
            .environment(\.shelfActions, appState.asShelfActions)
        let hostingView = SafeHostingView(pesto: rootView)
        // Suppress the blue accessibility/Liquid-Glass focus ring that macOS 26 draws
        // around the key window chrome. The panel is borderless; we draw our own shadow.
        hostingView.focusRingType = .none
        // Duplicates OverlayRootView's SwiftUI-level "Clipboard history" label one layer down, but
        // the hosting view is a distinct AX node and AccessibilityAuditTests fails if it is unnamed.
        hostingView.setAccessibilityLabel(String(localized: "Clipboard history"))
        panel.contentView = hostingView

        appState.onRestoreKeyFocus = { [weak self] in
            guard let self, self.appState.isOverlayVisible, !self.isHiding else { return }
            self.panel.makeKey()
        }
        panel.onEscapeKey = { [weak appState] in
            Task { @MainActor in appState?.close() }
        }
        appState.onClipDragStarted = { [weak self] in self?.beginDragClearance() }
    }

    /// While a clip is dragged out, only the command bar keeps the drag (`ShelfDragZone`): the rest of the shelf
    /// becomes invisible and click-through, so the app behind it, an input box under the glass, can take the drop. The
    /// button state is read directly because a drag session swallows the mouse events.
    private func beginDragClearance() {
        dragClearanceTimer?.invalidate()
        updateDragClearance()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDragClearance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragClearanceTimer = timer
    }

    private func updateDragClearance() {
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return endDragClearance() }
        let live = ShelfDragZone.isOverDropZone(pointer: NSEvent.mouseLocation, panelFrame: panel.frame)
        panel.alphaValue = live ? 1 : 0
        panel.ignoresMouseEvents = !live
    }

    /// A shelf that is closing after the drop stays invisible (`show()` resets it); one that stays open comes back.
    private func endDragClearance() {
        dragClearanceTimer?.invalidate()
        dragClearanceTimer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !isHiding, appState.isOverlayVisible else { return }
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
        }
    }

    func show() {
        PerfSignposts.shelf.begin("overlayShow").endAfterNextCommit()
        isHiding = false
        showGeneration += 1
        panel.contentView?.layer?.removeAnimation(forKey: "hideOverlay")
        let frame = BottomShelfPositioning.frame()
        panel.setFrame(frame, display: false)
        // Keep panel fully opaque — layer opacity drives the fade so we never touch
        // NSAnimatablePropertyContainer (panel.animator()), which would spin up NSAnimation
        // machinery and re-trigger the CA transaction / windowDidLayout crash.
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        dragClearanceTimer?.invalidate()
        dragClearanceTimer = nil

        // makeKeyAndOrderFront is required (not orderFrontRegardless) so .onKeyPress(.escape)
        // in SwiftUI fires. FocusRestoration.capture() was already called before show().
        panel.makeKeyAndOrderFront(nil)

        guard let layer = panel.contentView?.layer else { return }

        // Set model layer to final state; animation starts FROM the initial values.
        // When the animation is removed on completion, the presentation falls back to
        // model state (opacity=1, translation=0) — no fill-mode hacks needed.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = BottomShelfPositioning.position.slideOffset(height: BottomShelfPositioning.overlayHeight)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0

        let group = CAAnimationGroup()
        group.animations = PanelMotion.slides(reduceMotion: PanelMotion.systemReduceMotion) ? [slide, fade] : [fade]
        group.duration = 0.25
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0.75, 0.35, 1.0)
        group.fillMode = .backwards // hold fromValue at t=0 before animation runs
        group.isRemovedOnCompletion = true

        layer.add(group, forKey: "showOverlay")
        installMonitorsAndObservers()
        startAXPolling()
    }

    func hide(immediately: Bool = false, completion: (() -> Void)? = nil) {
        if isHiding {
            // Animation already in flight — chain completion so it fires after the current one.
            if let completion {
                let prior = pendingCompletion
                pendingCompletion = {
                    prior?()
                    completion()
                }
            }
            return
        }
        isHiding = true
        let hideGeneration = showGeneration
        HoverCardHost.shared.dismissAll()
        removeClickMonitor()
        stopAXPolling()
        let panelRef = panel
        guard let layer = panelRef.contentView?.layer, !immediately else {
            panelRef.orderOut(nil)
            isHiding = false
            completion?()
            return
        }

        // Set model layer to final opacity ONLY — deliberately do NOT set layer.transform
        // here. Setting a non-identity transform with setDisableActions(true) causes AppKit
        // to create a _NSWindowTransformAnimation to synchronize the window server with the
        // layer's visual position. On macOS 26 that internal animation crashes with SIGSEGV
        // (use-after-free in its dealloc) when it is drained from the autorelease pool during
        // the same CA transaction flush that fires this hide animation's completion block —
        // the completion block (which contains the paste trigger) never runs.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()

        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = 0
        // Explicit toValue instead of relying on model state.
        slide.toValue = BottomShelfPositioning.position.slideOffset(height: BottomShelfPositioning.overlayHeight)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        // opacity toValue is the model value (0)

        let group = CAAnimationGroup()
        group.animations = PanelMotion.slides(reduceMotion: PanelMotion.systemReduceMotion) ? [slide, fade] : [fade]
        group.duration = PanelMotion.hideDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // fillMode = .forwards keeps the slide's final transform (the panel height) visible until we
        // explicitly remove the animation in the completion block. isRemovedOnCompletion = false
        // prevents the auto-snap-back that would reveal the panel position before orderOut.
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        // CATransaction completion fires after all animations in this transaction finish.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // CATransaction completion blocks always fire on the main thread.
            MainActor.assumeIsolated {
                self?.finishHide(layer: layer, panel: panelRef, generation: hideGeneration, completion: completion)
            }
        }
        layer.add(group, forKey: "hideOverlay")
        CATransaction.commit()
    }

    private func finishHide(
        layer: CALayer,
        panel panelRef: NSPanel,
        generation: Int,
        completion: (() -> Void)?
    ) {
        let queued = { [self] in
            let queued = pendingCompletion
            pendingCompletion = nil
            queued?()
        }
        guard showGeneration == generation else {
            layer.removeAnimation(forKey: "hideOverlay")
            completion?()
            queued()
            return
        }
        // Remove the animation BEFORE orderOut. Since opacity model = 0, the panel is
        // invisible when the transform snaps from the offset back to identity — no visual flash.
        layer.removeAnimation(forKey: "hideOverlay")
        panelRef.orderOut(nil)
        // Reset layer to neutral so show() starts from a clean state.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        isHiding = false
        // Fire after orderOut so the target window has reclaimed key status.
        completion?()
        // Run any completion that arrived while this hide was in flight.
        queued()
    }

    // MARK: - Private

    private func installMonitorsAndObservers() {
        installClickMonitor()
        installDragEndMonitor()
        installResignKeyObserver()
        installAppActivateObserver()
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            guard !self.panel.frame.contains(mouse), !self.appState.keepsShelfOpenForAuthentication else { return }
            if self.appState.isQuickLookOpen {
                if QLPreviewPanel.sharedPreviewPanelExists(),
                   let ql = QLPreviewPanel.shared(),
                   ql.isVisible,
                   ql.frame.contains(mouse)
                {
                    return
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appState.isDragging = false // clear stale drag state if any
                self.onClickOutside?()
            }
        }
    }

    private func installDragEndMonitor() {
        guard dragEndMonitor == nil else { return }
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard let self, self.appState.isDragging else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appState.isDragging = false
                self.appState.draggingItemID = nil
                self.appState.draggingPinboardID = nil
                self.onClickOutside?()
            }
        }
    }

    private func installResignKeyObserver() {
        guard resignKeyObserver == nil else { return }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.appState.isOverlayVisible, !self.isHiding,
                      !self.appState.isDragging else { return }
                if self.appState.isQuickLookOpen || self.appState.keepsShelfOpenForAuthentication { return }
                if let key = NSApp.keyWindow {
                    if self.panel.childWindows?.contains(key) == true || key is QLPreviewPanel {
                        return
                    }
                }
                if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true {
                    return
                }
                self.onClickOutside?()
            }
        }
    }

    private func installAppActivateObserver() {
        guard appActivateObserver == nil else { return }
        appActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let activatedBundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, self.appState.isOverlayVisible, !self.isHiding,
                      !self.appState.isDragging else { return }
                if self.appState.isQuickLookOpen || self.appState.keepsShelfOpenForAuthentication { return }
                if let activatedBundleID, activatedBundleID != Bundle.main.bundleIdentifier {
                    self.onClickOutside?()
                }
            }
        }
    }

    private func startAXPolling() {
        guard axPollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.appState.recheckAccessibility()
        }
        timer.resume()
        axPollTimer = timer
    }

    private func stopAXPolling() {
        axPollTimer?.cancel()
        axPollTimer = nil
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
        if let obs = resignKeyObserver {
            NotificationCenter.default.removeObserver(obs)
            resignKeyObserver = nil
        }
        if let obs = appActivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivateObserver = nil
        }
    }
}
