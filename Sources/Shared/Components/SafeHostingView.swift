// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// NSHostingView subclass that prevents a re-entrant setNeedsUpdateConstraints crash on macOS 26.
///
/// Root cause: AppKit calls updateConstraints() inside NSPerformVisuallyAtomicChange. Inside that,
/// NSHostingView.updateConstraints() calls updateWindowContentSizeExtremaIfNecessary() → minSize
/// → _sizeThatFits → updateSize() → setProposedSize() → graphDidChange() → requestUpdate()
/// → setNeedsUpdate() → NSView.setNeedsUpdateConstraints(true) → _postWindowNeedsUpdateConstraints,
/// which throws an NSException because we are already inside NSPerformVisuallyAtomicChange.
/// The same re-entrant crash also occurs via the layout() → updateSize() path.
///
/// Fix: track when layout() or updateConstraints() is in progress and drop any nested
/// needsUpdateConstraints writes that would otherwise re-enter the window's constraint machinery.
///
/// IMPORTANT: every NSHostingView in the app must use this class — even non-overlay panels (e.g.,
/// AIResultPanelController). A single unguarded NSHostingView in any visible window is enough to
/// crash the process during AppKit's normal display-cycle constraint pass.
@MainActor
final class SafeHostingView: NSHostingView<AnyView> {
    private var inLayoutOrConstraints = false

    init(erasing rootView: some View) {
        super.init(rootView: AnyView(rootView))
        sizingOptions = []
    }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func layout() {
        inLayoutOrConstraints = true
        defer { inLayoutOrConstraints = false }
        super.layout()
    }

    override func updateConstraints() {
        inLayoutOrConstraints = true
        defer { inLayoutOrConstraints = false }
        super.updateConstraints()
    }

    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            guard !inLayoutOrConstraints else { return }
            super.needsUpdateConstraints = newValue
        }
    }
}
