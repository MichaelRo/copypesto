// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// A borderless, non-activating panel that can take typing without bringing Pesto forward, so the app being pasted into
/// stays frontmost (ADR 0009, ADR 0017).
final class FillInPromptPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        setAccessibilityRole(.window)
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel(String(localized: "Fill in snippet"))
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_: Any?) {
        onEscape?()
    }
}

/// Asks for the values a snippet needs, as part of the paste task: cancelling the task (sleep, lock, a newer paste)
/// closes the panel and answers nil, exactly as Escape does.
@MainActor
final class FillInPromptWindowController {
    private var panel: FillInPromptPanel?
    private var continuation: CheckedContinuation<SnippetFills?, Never>?

    var isShowing: Bool {
        continuation != nil
    }

    func ask(title: String, fields: [SnippetField], initial: SnippetFills) async -> SnippetFills? {
        guard !fields.isEmpty else { return initial }
        finish(nil)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<SnippetFills?, Never>) in
                self.continuation = continuation
                let model = FillInPromptModel(title: title, fields: fields, fills: initial)
                model.onSubmit = { [weak self, weak model] in self?.finish(model?.fills) }
                model.onCancel = { [weak self] in self?.finish(nil) }
                show(model)
                if Task.isCancelled { finish(nil) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(nil) }
        }
    }

    private func show(_ model: FillInPromptModel) {
        let panel = FillInPromptPanel()
        panel.onEscape = { [weak self] in self?.finish(nil) }
        let hosting = SafeHostingView(pesto: FillInPromptView(model: model))
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setContentSize(size)
        if let screen = TargetScreen.current() ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2 + frame.height / 8
            ))
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func finish(_ fills: SnippetFills?) {
        panel?.orderOut(nil)
        panel = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: fills)
    }
}
