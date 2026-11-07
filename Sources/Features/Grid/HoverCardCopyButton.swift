// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Copy Text in the hover card of a picture that read some text (ADR 0034): the accent text of the card, with a wash
/// behind it while the pointer is on it and a whole header row to aim at. After a click it says Copied for two seconds.
/// The hover card is a window that is never key, where SwiftUI's `onHover` is not reliable, so the pointer is read by a
/// tracking area (`PointerTracker`).
struct HoverCardCopyButton: View {
    static let height: CGFloat = 22
    static let washInset: CGFloat = 8
    static let trailingBleed: CGFloat = 8

    let quiet: Color
    let copy: () -> Bool
    @Environment(\.pestoAccent) private var accent
    @State private var hovering = false
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            guard copy() else { return }
            copied = true
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                copied = false
            }
        } label: {
            label
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(copied ? quiet : accent)
                .padding(.horizontal, Self.washInset)
                .frame(minHeight: Self.height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(hovering && !copied ? 0.14 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(PointerTracker(isInside: $hovering))
        .animation(Motion.animation(.pestoQuick), value: hovering)
        .padding(.trailing, -Self.trailingBleed)
        .accessibilityLabel(Text("Copy Recognized Text"))
        .onDisappear { resetTask?.cancel() }
    }

    @ViewBuilder
    private var label: some View {
        if copied {
            Label("Copied", systemImage: "checkmark")
        } else {
            Text("Copy Text")
        }
    }
}

/// Reports whether the pointer is over the view, in a window that is never key. It takes no clicks: the button under it
/// gets them.
private struct PointerTracker: NSViewRepresentable {
    @Binding var isInside: Bool

    func makeNSView(context _: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = { isInside = $0 }
        return view
    }

    func updateNSView(_ view: TrackingView, context _: Context) {
        view.onChange = { isInside = $0 }
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self
            ))
        }

        override func mouseEntered(with _: NSEvent) {
            onChange?(true)
        }

        override func mouseExited(with _: NSEvent) {
            onChange?(false)
        }
    }
}
