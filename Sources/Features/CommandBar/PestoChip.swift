// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// The one small filter/tag chip: a tinted capsule that is a real button with a comfortable target.
struct PestoChip: View {
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var differentiateOverride
    let label: String
    var icon: String?
    /// A picture in place of a symbol, such as an app's own icon on a source-app chip.
    var iconImage: NSImage?
    var tint: Color?
    let isActive: Bool
    /// The keyboard is on this chip (Tab in search): it is drawn with a focus ring.
    var hasKeyboardCursor = false
    /// When true (shelf app chips), shows only the icon at rest and opens the label on keyboard focus or
    /// selection.
    var collapsesLabel = false
    var helpText: String?
    /// Starts with the name already shown over the row; only tests set it.
    var startsPeeking = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var isOverPeek = false
    @State private var isPeeking: Bool
    @State private var peekTask: Task<Void, Never>?
    @FocusState private var isKeyboardFocused: Bool

    init(
        label: String, icon: String? = nil, iconImage: NSImage? = nil, tint: Color? = nil, isActive: Bool,
        hasKeyboardCursor: Bool = false, collapsesLabel: Bool = false, helpText: String? = nil,
        startsPeeking: Bool = false, action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.iconImage = iconImage
        self.tint = tint
        self.isActive = isActive
        self.hasKeyboardCursor = hasKeyboardCursor
        self.collapsesLabel = collapsesLabel
        self.helpText = helpText
        self.startsPeeking = startsPeeking
        self.action = action
        _isPeeking = State(initialValue: startsPeeking)
    }

    private var color: Color {
        tint ?? accent
    }

    private var hasFocus: Bool {
        hasKeyboardCursor || isKeyboardFocused
    }

    private var isLabelVisible: Bool {
        !collapsesLabel || isActive || hasFocus
    }

    private var fillOpacity: Double {
        if isActive { return 0.25 }
        return isHovered ? 0.18 : 0.10
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // A shape as well as a color: a selected chip must not depend on seeing the tint.
                if isActive, !collapsesLabel {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).accessibilityHidden(true)
                }
                if let iconImage {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                } else if let icon {
                    Image(systemName: icon)
                }
                if isLabelVisible {
                    Text(label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // A chip is as wide as its label up to 200 points (a collection named with a sentence no longer
                        // pushes the row into the toolbar): an active one, with its check mark, was cut to "Any ti…".
                        .frame(maxWidth: 200)
                        .fixedSize(horizontal: true, vertical: false)
                    if isActive, collapsesLabel {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.caption.weight(.medium))
            .padding(.leading, collapsesLabel ? 5 : 9)
            .padding(.trailing, collapsesLabel && !isLabelVisible ? 5 : 9)
            .frame(minWidth: 24, minHeight: 24)
            .fixedSize(horizontal: true, vertical: false)
            .background(Capsule().fill(color.opacity(fillOpacity)))
            // At standard contrast the tint alone marks an inactive chip; under
            // Increase Contrast it also gets a border, and its text goes to full opacity, instead
            // of leaning only on a low-opacity fill and dimmed text.
            .overlay(Capsule().strokeBorder(
                isActive ? color.opacity(0.5) : color.opacity(AdaptiveContrast.inactiveOutlineOpacity(
                    contrast: contrast, differentiateWithoutColor: differentiateOverride ?? systemDifferentiate
                )),
                lineWidth: differentiateOverride ?? systemDifferentiate ? 1 : 0.5
            ))
            // Primary text on a light tint of the accent always reads; accent-colored text could not for every accent.
            .foregroundStyle(isActive || isHovered || hasFocus || contrast == .increased ? Color.primary : Color.primary
                .opacity(0.75))
            .contentShape(Capsule())
            .overlay(Capsule().strokeBorder(accent, lineWidth: hasFocus ? 2 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .focused($isKeyboardFocused)
        .focusEffectDisabled()
        .overlay(alignment: .trailing) { peekedChip }
        .zIndex(isPeeking ? 1 : 0)
        .onHover { over in
            withAnimation(Motion.animation(.pestoQuick)) { isHovered = over }
            updatePointer()
        }
        .onChange(of: isLabelVisible) { _, visible in
            if visible { closePeek() }
        }
        .help(helpText ?? label)
        .accessibilityLabel(label)
        .accessibilityValue(collapsesLabel && isActive ? "selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(Motion.animation(.pestoQuick), value: isLabelVisible)
        .animation(Motion.animation(.pestoQuick), value: isActive)
    }

    /// The name opens over the row, never in it, growing leftward from the chip so the bar's scroll view never cuts it
    /// off at the right edge: neighbors keep their place, so the pointer cannot land on one of them
    /// because this chip grew. It opens after a short dwell and closes after a short grace, so crossing the row does
    /// not
    /// flicker every chip it passes.
    private func updatePointer() {
        setPointer(over: isHovered || isOverPeek)
    }

    private func closePeek() {
        peekTask?.cancel()
        isPeeking = false
        isOverPeek = false
    }

    private func setPointer(over: Bool) {
        peekTask?.cancel()
        guard collapsesLabel, !isLabelVisible || isPeeking else { return }
        peekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(over ? Self.peekDwellMilliseconds : Self.peekGraceMilliseconds))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.animation(.pestoQuick)) { isPeeking = over }
        }
    }

    static let peekDwellMilliseconds = 120
    static let peekGraceMilliseconds = 90

    @ViewBuilder
    private var peekedChip: some View {
        if isPeeking, collapsesLabel, !isLabelVisible {
            Button(action: action) {
                HStack(spacing: 4) {
                    if let iconImage {
                        Image(nsImage: iconImage).resizable().frame(width: 14, height: 14)
                    } else if let icon {
                        Image(systemName: icon)
                    }
                    Text(label).lineLimit(1).frame(maxWidth: 200).fixedSize(horizontal: true, vertical: false)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 9)
                .frame(minHeight: 24)
                .fixedSize()
                .background(Capsule().fill(.regularMaterial))
                .background(Capsule().fill(color.opacity(0.18)))
                .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .focusable(false)
            .onHover { over in
                isOverPeek = over
                updatePointer()
            }
            .transition(.opacity)
        }
    }
}
