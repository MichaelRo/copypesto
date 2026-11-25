// SPDX-License-Identifier: MIT
import SwiftUI

/// One letter on the search page (ADR 0066), drawn and pressed like iOS's: a callout over the key while it is held,
/// and after a moment the accents, chosen by sliding along them and typed on release. It types through `type`, which
/// the letters view routes to Pesto's own query only.
struct KeyboardLetterKey: View {
    let label: String
    let variants: [String]
    let size: CGSize
    let showsCallout: Bool
    let type: (String) -> Void

    @State private var isPressed = false
    @State private var showsVariants = false
    @State private var chosen = 0
    @State private var holdTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.pestoAccent) private var accent
    @Environment(\.pestoAccentLabel) private var accentLabel

    private var radius: CGFloat {
        sizeClass == .regular ? 7 : 5
    }

    private var keyFont: Font {
        size.height >= 40 ? .title2 : .title3
    }

    var body: some View {
        Text(verbatim: label)
            .font(keyFont)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(Color.primary)
            .frame(width: size.width, height: size.height)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KeyboardKeyStyle.fill(
                        isAccent: false, isFunction: false, pressed: isPressed && !showsCallout,
                        dark: colorScheme == .dark, accent: accent
                    ))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.6 : 0.35), radius: 0, x: 0, y: 1)
            }
            .overlay(alignment: .bottom) { pressedOverlay }
            .contentShape(.rect(cornerRadius: radius))
            .gesture(press)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityAddTraits(.isKeyboardKey)
            .accessibilityAction { type(label) }
            .accessibilityActions {
                ForEach(variants, id: \.self) { variant in
                    Button { type(variant) } label: { Text(verbatim: variant) }
                }
            }
            .zIndex(isPressed ? 1 : 0)
    }

    @ViewBuilder
    private var pressedOverlay: some View {
        if showsVariants {
            HStack(spacing: 0) {
                ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                    Text(verbatim: variant)
                        .font(keyFont)
                        .foregroundStyle(index == chosen ? accentLabel : Color.primary)
                        .frame(width: size.width, height: size.height)
                        .background(
                            index == chosen ? accent : .clear,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                        )
                }
            }
            .padding(4)
            .background(calloutFill, in: RoundedRectangle(cornerRadius: radius + 3, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            .fixedSize()
            .frame(width: size.width, alignment: .leading)
            .offset(y: -size.height - 6)
            .accessibilityHidden(true)
        } else if isPressed, showsCallout {
            Text(verbatim: label)
                .font(.largeTitle)
                .foregroundStyle(Color.primary)
                .frame(width: size.width * 1.45, height: size.height * 1.25)
                .background(calloutFill, in: RoundedRectangle(cornerRadius: radius + 3, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                .fixedSize()
                .offset(y: -size.height - 4)
                .accessibilityHidden(true)
        }
    }

    private var calloutFill: Color {
        colorScheme == .dark ? Color(white: 0.42) : .white
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressed {
                    isPressed = true
                    guard !variants.isEmpty else { return }
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(420))
                        guard !Task.isCancelled, isPressed else { return }
                        chosen = 0
                        showsVariants = true
                    }
                }
                if showsVariants {
                    let step = Int(((value.translation.width + size.width / 2) / size.width).rounded(.down))
                    chosen = min(max(step, 0), variants.count - 1)
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                let typed = showsVariants ? variants[chosen] : label
                isPressed = false
                showsVariants = false
                type(typed)
            }
    }
}
