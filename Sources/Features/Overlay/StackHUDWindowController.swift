// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

// MARK: - View model

/// Drives the HUD view — updated by AppDelegate as the stack advances.
@Observable
final class StackHUDViewModel {
    var progress: String = ""
    var preview: String = ""
    var totalCount: Int = 0
    /// True when the next clip is pasted by the person's own ⌘V, false when ⌘⇧V pastes it.
    var pastesWithCommandV = true
    /// What to press, from `StackHint`: the person's ⌘V, or the key bound to Open the shelf.
    var hint = ""
    var onCancel: (() -> Void)?

    func update(stack: PasteStack) {
        totalCount = stack.count
        if stack.isComplete {
            progress = "Done"
            preview = String(localized: "All \(stack.count) clips pasted")
        } else {
            progress = stack.progressLabel
            preview = stack.current?.previewText ?? ""
        }
    }
}

// MARK: - HUD view

private struct StackHUDView: View {
    @Environment(\.pestoAccent) private var accent
    @State var model: StackHUDViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.progress == "Done" ? "checkmark.circle.fill" : "square.stack.3d.up.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.progress == "Done" ? Color.green : accent)
                .contentTransition(Motion.reduceMotion ? .identity : .symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.progress == "Done" ? "All pasted" : "Pasting \(model.progress)")
                        // Text size capped: a fixed-size 300x54 NSPanel like ToastView's.
                            .scaledFont(size: 12, weight: .semibold, maxScale: 1.3)
                            .foregroundStyle(.primary)

                    if model.progress != "Done" {
                        Text("· \(model.hint)")
                            .scaledFont(size: 11, maxScale: 1.3)
                            .pestoQuiet()
                            .accessibilityLabel(model.hint)
                    }
                }

                Text(model.preview)
                    .scaledFont(size: 11, maxScale: 1.3)
                    .pestoQuiet()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if model.progress != "Done" {
                Spacer(minLength: 4)
                Button("Cancel") { model.onCancel?() }
                    .buttonStyle(.pestoLink)
                    .scaledFont(size: 11, maxScale: 1.3)
                    .accessibilityIdentifier(AccessibilityID.stackCancelButton)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 340, alignment: .leading)
        .glassPanelBackground(in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .animation(Motion.animation(.easeInOut(duration: 0.2)), value: model.progress)
    }
}

// MARK: - Controller

/// Manages the lifecycle of the stack progress HUD.
///
/// The HUD is shown when a stack is activated and dismissed when it is complete
/// (either all items pasted or the stack is cancelled). It updates in place
/// as `advance()` is called — no recreate needed.
@MainActor
final class StackHUDWindowController {
    private var panel: NSPanel?
    private let viewModel = StackHUDViewModel()
    private var dismissTask: Task<Void, Never>?

    /// Called when the person presses Cancel on the HUD.
    var onCancel: (() -> Void)? {
        get { viewModel.onCancel }
        set { viewModel.onCancel = newValue }
    }

    func show(stack: PasteStack, pastesWithCommandV: Bool = false) {
        viewModel.pastesWithCommandV = pastesWithCommandV
        viewModel.hint = StackHint.text(
            pastesWithCommandV: pastesWithCommandV, openShelf: GlobalShortcut.openShelf.binding(in: AppDefaults.store)
        )
        viewModel.update(stack: stack)
        announce(stack)
        if let panel {
            panel.orderFront(nil)
        } else {
            createPanel()
            slideIn()
        }
    }

    func update(stack: PasteStack) {
        viewModel.update(stack: stack)
        announce(stack)

        if stack.isComplete {
            // Brief "Done" display before auto-dismiss.
            dismissTask?.cancel()
            dismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1400))
                self?.hide()
            }
        }
    }

    private func announce(_ stack: PasteStack) {
        if stack.isComplete {
            StackAnnouncement.complete()
        } else {
            StackAnnouncement.progress(
                position: stack.currentIndex + 1, count: stack.items.count,
                hint: viewModel.hint
            )
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Private

    /// Drops in from the top edge, as Motion's `pestoMove` does for views; with Reduce Motion it just appears.
    private func slideIn() {
        guard let panel else { return }
        guard !Motion.reduceMotion else { return panel.orderFront(nil) }
        let resting = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: resting.x, y: resting.y + 14))
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(resting)
            panel.animator().alphaValue = 1
        }
    }

    private func createPanel() {
        let hudView = StackHUDView(model: viewModel)
        let hosting = SafeHostingView(pesto: hudView)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 54)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 54),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.contentView = hosting
        positionPanel(newPanel)

        panel = newPanel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = TargetScreen.current() ?? NSScreen.main else { return }
        let sf = screen.visibleFrame
        let pw = panel.frame.width
        let ph = panel.frame.height
        let origin = NSPoint(
            x: sf.maxX - pw - 16,
            y: sf.maxY - ph - 8
        )
        panel.setFrameOrigin(origin)
    }
}
