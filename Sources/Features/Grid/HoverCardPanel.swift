// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// The window that holds the shelf's hover card. It is a child of the shelf (or the floating window) so it follows it
/// across Spaces and closes with it, and it never becomes key or main, so a click on a card under it still lands
/// and the shelf keeps the keyboard.
@MainActor
final class HoverCardPanel: NSPanel {
    var onPointerInside: ((Bool) -> Void)?
    private let container = HoverCardContainer()
    let hosting = SafeHostingView(pesto: EmptyView())

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        setAccessibilityRole(.window)
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel(String(localized: "Clip details"))
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.onPointerInside = { [weak self] inside in self?.onPointerInside?(inside) }
        contentView = container
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Reports the pointer entering and leaving the card. SwiftUI's `onHover` is not reliable in a window that is never
/// key, so this uses a tracking area that is active regardless.
@MainActor
private final class HoverCardContainer: NSView {
    var onPointerInside: ((Bool) -> Void)?

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self
        ))
    }

    override func mouseEntered(with _: NSEvent) {
        onPointerInside?(true)
    }

    override func mouseExited(with _: NSEvent) {
        onPointerInside?(false)
    }
}

/// One panel for the whole app: only one card is ever open, and a new one replaces the old at once.
@MainActor
final class HoverCardHost {
    static let shared = HoverCardHost()

    /// Above the top edge of the shelf (or the floating window), so the card never covers the chip bar or the clips.
    private static let gap: CGFloat = 8
    private static let edgeInset: CGFloat = 12

    private let panel = HoverCardPanel()
    private var owner: UUID?
    private var anchor: NSView?
    private var contentSize: CGSize = .zero
    private var onReplaced: (() -> Void)?
    private var onEscape: (() -> Void)?
    private var settleTask: Task<Void, Never>?
    private var presenting: PerfInterval?

    private init() {
        panel.onPointerInside = { [weak self] inside in self?.pointerInside?(inside) }
    }

    private var pointerInside: ((Bool) -> Void)?

    struct Request {
        let owner: UUID
        let anchor: NSView
        /// A card with nothing to scroll lets every click and the pointer through.
        let scrolls: Bool
        let content: () -> AnyView
        let onPointerInside: (Bool) -> Void
        let onReplaced: () -> Void
        let onEscape: () -> Void
    }

    func present(_ request: Request) {
        if let current = owner, current != request.owner {
            let replaced = onReplaced
            Task { @MainActor in replaced?() }
        }
        let isNew = owner != request.owner
        if isNew {
            presenting?.end()
            presenting = PerfSignposts.shelf.begin("hoverCardPresent")
        }
        owner = request.owner
        anchor = request.anchor
        onReplaced = request.onReplaced
        onEscape = request.onEscape
        pointerInside = request.onPointerInside
        panel.ignoresMouseEvents = !request.scrolls
        if isNew { contentSize = .zero }
        panel.hosting.setPestoRoot(
            HoverCardEntrance(
                content: request.content(), opensAbove: request.anchor.window.map(Self.opensAbove(over:)) ?? true
            )
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in
                self?.sizeChanged(size)
            }
            .id(request.owner)
        )
        guard let parent = request.anchor.window else { return }
        if panel.parent != parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        if contentSize != .zero { reposition() }
    }

    /// The first Esc closes the card and only the card; the next one closes the shelf. False when none is open.
    func closeForEscape() -> Bool {
        guard owner != nil, panel.isVisible else {
            dismissAll()
            return false
        }
        let escape = onEscape
        dismissAll()
        escape?()
        return true
    }

    func dismissAll() {
        guard let current = owner else { return }
        dismiss(owner: current)
    }

    func dismiss(owner dismissed: UUID) {
        guard owner == dismissed else { return }
        owner = nil
        anchor = nil
        onReplaced = nil
        onEscape = nil
        pointerInside = nil
        contentSize = .zero
        settleTask?.cancel()
        panel.hosting.setPestoRoot(EmptyView())
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// The first size can be the pre-measurement one, so the panel is shown a moment later, at the size the content
    /// settled on, rather than flashing at the wrong one.
    private func sizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        settleTask?.cancel()
        let visible = panel.isVisible
        settleTask = Task { @MainActor [weak self] in
            if visible { await Task.yield() } else { try? await Task.sleep(for: .milliseconds(30)) }
            guard !Task.isCancelled else { return }
            self?.reposition()
        }
    }

    static func opensAbove(over window: NSWindow) -> Bool {
        ShelfPosition.hoverCardOpensAbove(
            hostIsShelf: window is OverlayPanel,
            position: BottomShelfPositioning.position
        )
    }

    /// Centred over the clip it describes and kept inside the shelf and the screen.
    private func reposition() {
        guard contentSize != .zero, let anchor, let window = anchor.window else { return }
        let card = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? .infinite
        let bounds = window.frame.intersection(screen).insetBy(dx: Self.edgeInset, dy: 0)
        let width = contentSize.width
        let height = contentSize.height
        let x = min(max(card.midX - width / 2, bounds.minX), max(bounds.minX, bounds.maxX - width))
        let opensAbove = Self.opensAbove(over: window)
        let y = opensAbove
            ? min(window.frame.maxY + Self.gap, screen.maxY - height)
            : max(window.frame.minY - Self.gap - height, screen.minY)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if !panel.isVisible { panel.orderFront(nil) }
        presenting?.end()
        presenting = nil
    }
}

/// The card scales in from 97% and fades over a quick spring; with Reduce Motion it is simply there.
private struct HoverCardEntrance: View {
    let content: AnyView
    /// The card grows out of the edge it touches: the bottom when it sits above the shelf, the top when below it.
    let opensAbove: Bool
    @State private var shown = false

    var body: some View {
        content
            .scaleEffect(shown || Motion.reduceMotion ? 1 : 0.97, anchor: opensAbove ? .bottom : .top)
            .opacity(shown || Motion.reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(Motion.animation(.pestoQuick)) { shown = true }
            }
    }
}

private struct HoverCardAnchor: NSViewRepresentable {
    let owner: UUID
    @Binding var isPresented: Bool
    let scrolls: Bool
    let onPointerInside: (Bool) -> Void
    let onEscape: () -> Void
    let content: () -> AnyView

    final class Coordinator {
        let owner: UUID

        init(owner: UUID) {
            self.owner = owner
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: owner)
    }

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ anchor: NSView, context _: Context) {
        if isPresented, anchor.window != nil {
            HoverCardHost.shared.present(.init(
                owner: owner, anchor: anchor, scrolls: scrolls, content: content,
                onPointerInside: onPointerInside,
                onReplaced: { [binding = $isPresented] in binding.wrappedValue = false },
                onEscape: onEscape
            ))
        } else {
            HoverCardHost.shared.dismiss(owner: owner)
        }
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        let owner = coordinator.owner
        Task { @MainActor in HoverCardHost.shared.dismiss(owner: owner) }
    }
}

struct HoverCardCallbacks {
    /// The pointer entering and leaving the card.
    let onPointerInside: (Bool) -> Void
    let onEscape: () -> Void
}

extension View {
    /// Shows `content` in the hover-card panel above this view while `isPresented`. `scrolls` says whether the card
    /// takes the pointer (it has something to scroll).
    func hoverCard(
        owner: UUID, isPresented: Binding<Bool>, scrolls: Bool, callbacks: HoverCardCallbacks,
        content: @escaping () -> some View
    )
    -> some View {
        background(HoverCardAnchor(
            owner: owner, isPresented: isPresented, scrolls: scrolls, onPointerInside: callbacks.onPointerInside,
            onEscape: callbacks.onEscape, content: { AnyView(content()) }
        ))
    }
}
