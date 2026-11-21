// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

// MARK: - Result view

enum AIResultTitle {
    static func coverageNote(_ coverage: AIResult.Coverage) -> String {
        coverage.note
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
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
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

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let contentView,
           contentView.bounds.height > 80
        {
            let point = contentView.convert(event.locationInWindow, from: nil)
            if point.y >= contentView.bounds.height - 44,
               !Self.isInCloseButtonZone(point, in: contentView),
               !(contentView.hitTest(event.locationInWindow) is NSControl)
            {
                NSCursor.closedHand.push()
                performDrag(with: event)
                NSCursor.pop()
                return
            }
        }
        super.sendEvent(event)
    }

    static func isInCloseButtonZone(_ point: NSPoint, in contentView: NSView) -> Bool {
        guard point.y >= contentView.bounds.height - 44 else { return false }
        if contentView.userInterfaceLayoutDirection == .rightToLeft {
            return point.x <= 56
        }
        return point.x >= contentView.bounds.width - 56
    }
}

extension AppState {
    var keepsShelfOpenForModal: Bool {
        keepsShelfOpenForAuthentication || isTextEditorOpen || isQuickLookOpen || isAIResultOpen
    }

    func handleAIResultChange() {
        if let aiResult {
            isAIResultOpen = true
            onAIResult?(aiResult)
        } else {
            // The panel closed, or the history locked: what was left of a long text is dropped with it.
            aiRun = nil
            aiPartTask?.cancel()
            aiPartTask = nil
            onAIResultCleared?()
            if !aiIsLoading, isAIResultOpen {
                isAIResultOpen = false
                onRestoreKeyFocus?()
            }
        }
    }

    func handleAILoadingChange() {
        if aiIsLoading {
            isAIResultOpen = true
            onAILoading?()
        } else if aiResult == nil, isAIResultOpen {
            isAIResultOpen = false
            onRestoreKeyFocus?()
        }
    }
}

private struct AIResultView: View {
    @Environment(\.pestoAccent) private var accent
    let result: AIResult
    var onClose: () -> Void
    var onPaste: () -> Void
    var onCopy: () -> Void
    var onReadNext: () -> Void = {}
    var onCancelPart: () -> Void = {}
    var onCombine: () -> Void = {}

    @State private var copied = false
    @State private var scrollEnds = ScrollEnds()
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
            .onScrollGeometryChange(for: ScrollEnds.self, of: { ScrollEnds($0) }, action: { _, ends in
                scrollEnds = ends
            })
            .mask(
                VStack(spacing: 0) {
                    Color.black
                    if !scrollEnds.atBottom {
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 22)
                    }
                }
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
                        onCopy()
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
                    .animation(Motion.animation(.pestoQuick), value: copied)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : 0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Loading view

private struct AILoadingView: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking…")
                .scaledFont(size: 12.5)
                .pestoQuiet()
        }
        .padding(20)
        .background {
            shape.fill(Color.opaqueSurface.opacity(0.92)).adaptiveMaterialBackground(in: shape)
        }
        .overlay(
            shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : 0.14), lineWidth: 1)
        )
        .clipShape(shape)
    }
}

// MARK: - Controller

/// Manages a floating panel that shows the AI action result (or a loading spinner).
@MainActor
final class AIResultPanelController {
    private(set) var panel: NSPanel?
    private(set) var isOpen = false
    var onStateChanged: (@MainActor (Bool) -> Void)?
    var onClose: (@MainActor () -> Void)?

    func showLoading() {
        show(content: SafeHostingView(pesto: AILoadingView()), size: NSSize(width: 340, height: 60))
    }

    func showResult(
        _ result: AIResult, onClose: @escaping () -> Void, onPaste: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onReadNext: @escaping () -> Void = {}, onCancelPart: @escaping () -> Void = {},
        onCombine: @escaping () -> Void = {}
    ) {
        let view = AIResultView(
            result: result, onClose: onClose, onPaste: onPaste, onCopy: onCopy,
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
        show(content: hosting, size: NSSize(width: width, height: height), onEscape: onClose)
    }

    func hide() {
        let wasOpen = isOpen
        isOpen = false
        tearDownPanel()
        if wasOpen {
            onStateChanged?(false)
            onClose?()
        }
    }

    // MARK: - Private

    private func tearDownPanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func show(content: NSView, size: NSSize, onEscape: (() -> Void)? = nil) {
        // A part that came in replaces the panel in the same place, so a panel the person moved does not jump back.
        let previousFrame = panel?.frame
        let wasOpen = isOpen
        tearDownPanel()

        content.frame = NSRect(origin: .zero, size: size)
        content.wantsLayer = true
        content.layer?.cornerRadius = 16
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true

        let newPanel = AIResultPanel(size: size) { [weak self] in
            if let onEscape {
                onEscape()
            } else {
                self?.hide()
            }
        }
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
        isOpen = true
        if !wasOpen { onStateChanged?(true) }
        newPanel.makeKeyAndOrderFront(nil)
        newPanel.invalidateShadow()
        panel = newPanel
    }
}
