// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftUI

/// Opens the focused card's own context menu from the keyboard. SwiftUI offers no call to open a `.contextMenu`, so
/// the card reports a view and a right-click is posted at its centre: the menu stays one definition, the one a mouse
/// and VoiceOver already use.
@MainActor
final class FocusedCardAnchor {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ShelfActions")

    private struct WeakView {
        weak var view: NSView?
    }

    private var registered: [WeakView] = []

    /// SwiftUI makes a representable's view more than once, and some of them live a few milliseconds: with one slot,
    /// a throwaway view made after the real one replaced it and ⌘K found nothing (the log of 2026-10-21). Every view
    /// is kept, weakly, and the one that is in a window, the newest if there are two, is the focused card.
    func register(_ view: NSView) {
        registered.removeAll { $0.view == nil || $0.view === view }
        registered.append(WeakView(view: view))
    }

    var liveView: NSView? {
        registered.last { $0.view?.window != nil }?.view
    }

    /// False when no focused card is on screen: the grid builds only the cards near the viewport.
    var hasView: Bool {
        liveView != nil
    }

    private var made = 0
    private var lastMade: ContinuousClock.Instant?

    func noteMade() {
        made += 1
        lastMade = .now
    }

    private var history: String {
        let ago = lastMade.map { Int(($0.duration(to: .now)) / .milliseconds(1)) }.map(String.init) ?? "never"
        return "made=\(made) lastMadeMsAgo=\(ago)"
    }

    /// Every way this can do nothing says so in the log (`make logs CATEGORY=ShelfActions`), with geometry and class
    /// names only, never a clip's content: ⌘K was reported as silent on some cards and the cause is not visible in
    /// the code.
    /// ⌘K arrives while SwiftUI is still replacing the card that just took the focus: in the log of 2026-10-21 the
    /// view was gone 350 to 530 ms after it was made, on 12 of 18 presses. The grid builds the new one a moment
    /// later, so wait up to a second for it before giving up.
    func showActionsWhenReady(context: String = "") async {
        let ready = await PollUntil.holds(timeout: .seconds(1), interval: .milliseconds(50)) { [weak self] in
            self?.hasView == true
        }
        Self.logger.notice("[wait] cardViewReady=\(ready, privacy: .public) \(context, privacy: .public)")
        showActions(context: context)
    }

    func showActions(context: String = "") {
        guard let view = liveView else {
            let history = history
            Self.logger
                .notice("[end] outcome=no-focused-card-view \(context, privacy: .public) \(history, privacy: .public)")
            return
        }
        guard let window = view.window else {
            Self.logger.notice("[end] outcome=focused-card-view-has-no-window \(context, privacy: .public)")
            return
        }
        guard !view.visibleRect.isEmpty else {
            Self.logger
                .notice(
                    "[end] outcome=focused-card-not-visible bounds=\(NSStringFromRect(view.bounds), privacy: .public)"
                )
            return
        }
        let frame = view.convert(view.visibleRect, to: nil)
        guard let click = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: frame.midX, y: frame.midY),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            Self.logger.notice("[end] outcome=could-not-make-the-click")
            return
        }
        let hit = window.contentView?.superview?.hitTest(click.locationInWindow)
            .map { String(describing: type(of: $0)) } ?? "nothing"
        let at = NSStringFromPoint(click.locationInWindow)
        let key = window.isKeyWindow
        Self.logger.notice("[end] outcome=right-click-posted at=\(at, privacy: .public) hit=\(hit, privacy: .public)")
        Self.logger.notice("[end] windowIsKey=\(key, privacy: .public)")
        window.sendEvent(click)
    }
}

struct FocusedCardAnchorView: NSViewRepresentable {
    let anchor: FocusedCardAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchor.register(view)
        anchor.noteMade()
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        anchor.register(view)
    }
}
