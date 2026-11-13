// SPDX-License-Identifier: MIT
import SwiftUI

/// The shelf bar's icon buttons (search, new collection, floating window, Settings) drawn as the chips beside them:
/// the same 24 pt capsule, the same quiet fill that brightens under the pointer, and the same outline under Increase
/// Contrast, in the neutral ink so a button never competes with a collection's colour.
struct ShelfBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
        @Environment(\.differentiateWithoutColorOverride) private var differentiateOverride
        @State private var isHovered = false

        private var fillOpacity: Double {
            if configuration.isPressed { return 0.22 }
            return isHovered ? 0.18 : 0.10
        }

        var body: some View {
            configuration.label
                .frame(minWidth: 32, minHeight: 24)
                .background(Capsule().fill(Color.primary.opacity(fillOpacity)))
                .overlay(Capsule().strokeBorder(
                    Color.primary.opacity(AdaptiveContrast.inactiveOutlineOpacity(
                        contrast: contrast, differentiateWithoutColor: differentiateOverride ?? systemDifferentiate
                    )),
                    lineWidth: 1
                ))
                .contentShape(Capsule())
                .onHover { over in
                    withAnimation(Motion.animation(.pestoQuick)) { isHovered = over }
                }
        }
    }
}
