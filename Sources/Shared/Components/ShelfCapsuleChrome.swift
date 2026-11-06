// SPDX-License-Identifier: MIT
import SwiftUI

struct ShelfCapsuleChrome: ViewModifier {
    @Environment(\.pestoAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var differentiateOverride

    private var strongBorder: Bool {
        contrast == .increased || (differentiateOverride ?? systemDifferentiate)
    }

    func body(content: Content) -> some View {
        content
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
}

extension View {
    func shelfCapsuleChrome() -> some View {
        modifier(ShelfCapsuleChrome())
    }
}
