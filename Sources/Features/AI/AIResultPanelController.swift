// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

// MARK: - Result view

enum AIResultTitle {
    static func coverageNote(_ coverage: AIResult.Coverage) -> String {
        let shown = coverage.shown.formatted(), total = coverage.total.formatted()
        return String(localized: "Based on the first \(shown) of \(total) characters.")
    }

    static func text(action: String, isError: Bool) -> String {
        isError ? "\(action) failed" : action
    }
}

/// A floating panel that can take keyboard focus without activating Pesto: Copy, Done and Close must be reachable
/// from the keyboard, and Escape must dismiss it.
final class AIResultPanel: NSPanel {
    private let onEscape: () -> Void

    init(size: NSSize, onEscape: @escaping () -> Void) {
        self.onEscape = onEscape
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        setAccessibilityRole(.window)
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel(String(localized: "AI result"))
    }

    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_: Any?) {
        onEscape()
    }
}

private struct AIResultView: View {
    @Environment(\.pestoAccent) private var accent
    let result: AIResult
    var onClose: () -> Void
    var onPaste: () -> Void
    var onReadNext: () -> Void = {}
    var onCancelPart: () -> Void = {}
    var onCombine: () -> Void = {}

    @State private var copied = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: result.isError ? "exclamationmark.triangle.fill" : result.action.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(result.isError ? Color.statusBad : accent)
                    .accessibilityHidden(true)

                Text(AIResultTitle.text(action: result.action.rawValue, isError: result.isError))
                    .scaledFont(size: 13, weight: .semibold)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.16)))
                        .pestoHitTarget(28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()

            if !result.sourcePreview.isEmpty {
                let ellipsis = result.sourcePreview.count >= 80 ? "…" : ""
                Text("\u{201C}\(result.sourcePreview)\(ellipsis)\u{201D}")
                    .scaledFont(size: 10)
                    .foregroundStyle(.primary.opacity(contrast == .increased ? 0.9 : 0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            if let coverage = result.coverage, coverage.isPartial {
                Text(AIResultTitle.coverageNote(coverage))
                    .pestoCaption()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 10)

            ScrollView {
                if let progress = result.progress {
                    AIPartsList(progress: progress, combined: progress.hasCombined ? result.result : nil)
                } else {
                    Text(result.result)
                        .scaledFont(size: 12.5)
                        .foregroundStyle(result.isError ? Color.statusBad : .primary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
            .frame(
                height: result.progress == nil
                    ? AIResultLayout.answerHeight(for: result.result, width: AIResultLayout.textWidth)
                    : 220
            )
            .accessibilityLabel(result.progress == nil ? "Answer" : "Parts read so far")

            if let progress = result.progress {
                AIPartsControls(
                    progress: progress, onReadNext: onReadNext, onCancel: onCancelPart, onCombine: onCombine
                )
            }

            Divider()
                .padding(.horizontal, 16)

            HStack {
                if result.canPaste {
                    Button {
                        onPaste()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Paste")
                            Image(systemName: "return")
                                .accessibilityHidden(true)
                        }
                        .scaledFont(size: 11.5, weight: .medium)
                    }
                    .buttonStyle(.pestoCapsule(.primary))
                    .keyboardShortcut(.defaultAction)
                    .help("Paste into the app you were using")
                    .accessibilityIdentifier(AccessibilityID.aiResultPasteButton)
                }
                if !result.isError {
                    Button {
                        AppPasteboard.general.clearContents()
                        AppPasteboard.general.setString(result.result, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy Result", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .scaledFont(size: 11.5, weight: .medium)
                    }
                    .buttonStyle(.pestoCapsule(.secondary))
                    .animation(Motion.animation(.easeOut(duration: 0.15)), value: copied)
                }
                Spacer()
                Button("Done") { onClose() }
                    .buttonStyle(.pestoCapsule(.secondary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(Color.opaqueSurface.opacity(0.92)).adaptiveMaterialBackground(in: shape)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Loading view

private struct AILoadingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking…")
                .scaledFont(size: 12.5)
                .pestoQuiet()
        }
        .padding(20)
        .glassPanelBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Controller

/// Manages a floating panel that shows the AI action result (or a loading spinner).
@MainActor
final class AIResultPanelController {
    private var panel: NSPanel?

    func showLoading() {
        show(content: SafeHostingView(pesto: AILoadingView()), size: NSSize(width: 340, height: 60))
    }

    func showResult(
        _ result: AIResult, onClose: @escaping () -> Void, onPaste: @escaping () -> Void,
        onReadNext: @escaping () -> Void = {}, onCancelPart: @escaping () -> Void = {},
        onCombine: @escaping () -> Void = {}
    ) {
        let view = AIResultView(
            result: result, onClose: onClose, onPaste: onPaste,
            onReadNext: onReadNext, onCancelPart: onCancelPart, onCombine: onCombine
        )
        let width = AIResultLayout.panelWidth
        let hosting = SafeHostingView(pesto: view.frame(width: width))
        hosting.setAccessibilityLabel(String(localized: "AI answer"))
        // 340 wide; the height is what the content needs (a short answer no longer leaves an empty panel under it), up
        // to what the scroll area and its parts controls allow.
        // A hosting view that does not drive its window reports no fitting size, so the height came back as the 170 pt
        // floor and the panel grew to its real 362 pt after it was placed: each part's panel was then placed off its
        // middle and drifted down the display until its buttons were off it. A hosting controller measures the content.
        let needed = NSHostingController(rootView: view.frame(width: width))
            .sizeThatFits(in: CGSize(width: width, height: AIResultLayout.maximumMeasuredHeight)).height
        let visible = (TargetScreen.current() ?? NSScreen.main)?.visibleFrame.height ?? 900
        let cap = AIResultLayout.panelCap(visibleHeight: visible, readsInParts: result.progress != nil)
        let height = min(max(needed, 170), cap)
        show(content: hosting, size: NSSize(width: width, height: height))
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Private

    private func show(content: NSView, size: NSSize) {
        // A part that came in replaces the panel in the same place, so a panel the person moved does not jump back.
        let previousFrame = panel?.frame
        hide()

        content.frame = NSRect(origin: .zero, size: size)

        let newPanel = AIResultPanel(size: size) { [weak self] in self?.hide() }
        newPanel.contentView = content

        if let previousFrame {
            // It grows around its middle, not from its bottom edge: an answer that gained a part stayed anchored at the
            // bottom and ended against the display's edge, where the Dock covers its buttons.
            newPanel.setFrameOrigin(NSPoint(
                x: previousFrame.midX - size.width / 2, y: previousFrame.midY - size.height / 2
            ))
        } else if let screen = TargetScreen.current() ?? NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.midX - size.width / 2
            let y = sf.midY - size.height / 2 + sf.height * 0.1
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // A panel that grew where an earlier, smaller one stood must not end past the display's edge, where its buttons
        // cannot be reached.
        if let visible = (TargetScreen.current() ?? NSScreen.main)?.visibleFrame {
            newPanel.setFrame(
                FloatingWindowPlacement.fit(newPanel.frame, in: visible.insetBy(dx: 0, dy: 24)),
                display: false
            )
        }
        newPanel.makeKeyAndOrderFront(nil)
        panel = newPanel
    }
}
