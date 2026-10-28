// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What the shelf offers once two or more clips are selected, as one floating capsule in the band under the cards.
/// It hugs its content and sits at the trailing edge, so Paste One by One and Delete stay put when Paste All comes and
/// goes.
struct SelectionActionBar: View {
    let count: Int
    let canPasteAll: Bool
    let onPasteAll: () -> Void
    let onPasteOneByOne: () -> Void
    let onDelete: () -> Void

    /// The capsule is 30 pt tall in the 46 pt band under the cards (half the lift room and the bottom slot), which
    /// leaves 8 pt above it and below it.
    static let bottomInset: CGFloat = (ShelfHeight.liftRoom / 2 + ShelfHeight.bottomSlot - 30) / 2

    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var differentiateOverride

    private var strongBorder: Bool {
        contrast == .increased || (differentiateOverride ?? systemDifferentiate)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            capsule(showsHint: true, iconOnly: false)
            capsule(showsHint: false, iconOnly: false)
            capsule(showsHint: false, iconOnly: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection actions")
    }

    private func capsule(showsHint: Bool, iconOnly: Bool) -> some View {
        HStack(spacing: 0) {
            selectionState(showsHint: showsHint)
            divider
            actions(iconOnly: iconOnly)
        }
        .padding(.leading, 14)
        .padding([.vertical, .trailing], 3)
        .fixedSize(horizontal: true, vertical: false)
        .background(background)
        .overlay(Capsule().strokeBorder(accent.opacity(strongBorder ? 0.7 : 0.35), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.1), radius: 10, y: 3)
        .shadow(color: .black.opacity(0.08), radius: 1)
    }

    private var background: some View {
        ZStack {
            if scheme == .dark {
                Capsule().fill(Color.black.opacity(0.85))
            }
            Capsule().adaptiveMaterialFill()
            Capsule().fill(accent.opacity(0.12))
        }
    }

    private func selectionState(showsHint: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(verbatim: "\(count)")
                    .scaledFont(size: 12, weight: .semibold, maxScale: 1.3)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Motion.animation(.pestoQuick), value: count)
                Text("selected")
                    .scaledFont(size: 12, maxScale: 1.3)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            // Spoken as the clips are picked by `SelectionAnnouncement`; the label is for a swipe onto the bar.
            .accessibilityLabel("\(count) clips selected")
            .accessibilityHint(showsHint ? "Press Escape to clear" : "")
            if showsHint {
                clearHint.padding(.leading, 4)
            }
        }
    }

    private var clearHint: some View {
        HStack(spacing: 5) {
            Keycap(symbol: "esc", size: .compact)
            Text("to clear")
                .scaledFont(size: 11, maxScale: 1.3)
                .foregroundStyle(.primary)
        }
        .accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 10)
            .accessibilityHidden(true)
    }

    private struct BarAction {
        let title: LocalizedStringKey
        let icon: String
        let role: PestoCapsuleButtonStyle.Role
        let help: LocalizedStringKey
        var shortcut: String?
    }

    private func actions(iconOnly: Bool) -> some View {
        HStack(spacing: 4) {
            if canPasteAll {
                actionButton(
                    BarAction(
                        title: "Paste All", icon: "text.append", role: .primary,
                        help: "Join the selected clips with a blank line and paste them at once (\u{2318}P)",
                        shortcut: "\u{2318}P"
                    ),
                    iconOnly: iconOnly, action: onPasteAll
                )
                .accessibilityIdentifier(AccessibilityID.pasteAllButton)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            }
            actionButton(
                BarAction(
                    title: "Paste One by One", icon: "square.stack.3d.up.fill",
                    role: canPasteAll ? .secondary : .primary,
                    help: "Paste one selected clip each time you press ⌘V (\u{21E7}\u{2318}P)",
                    shortcut: "\u{21E7}\u{2318}P"
                ),
                iconOnly: iconOnly, action: onPasteOneByOne
            )
            .accessibilityIdentifier(AccessibilityID.pasteOneByOneButton)
            actionButton(
                BarAction(title: "Delete", icon: "trash", role: .destructive, help: "Delete the selected clips"),
                iconOnly: iconOnly, action: onDelete
            )
            .accessibilityIdentifier(AccessibilityID.deleteSelectedButton)
        }
        .animation(Motion.animation(.pestoQuick), value: canPasteAll)
    }

    private func actionButton(_ spec: BarAction, iconOnly: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(spec.title, systemImage: spec.icon)
                    .scaledFont(size: 12, weight: .semibold, maxScale: 1.3)
                    .modifier(IconOnlyIf(iconOnly))
                if let shortcut = spec.shortcut, !iconOnly {
                    Text(shortcut)
                        .scaledFont(size: 10.5, weight: .medium, maxScale: 1.3)
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.pestoCapsule(spec.role))
        .help(spec.help)
    }
}

private struct IconOnlyIf: ViewModifier {
    let iconOnly: Bool

    init(_ iconOnly: Bool) {
        self.iconOnly = iconOnly
    }

    func body(content: Content) -> some View {
        if iconOnly {
            content.labelStyle(.iconOnly)
        } else {
            content
        }
    }
}
