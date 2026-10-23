// SPDX-License-Identifier: MIT
import SwiftUI

/// The capsule button of a floating bar: one 24 pt shape in three weights, so a row of actions reads as a primary
/// action, quiet ones and a destructive one without leaning on colour alone (every button keeps its icon and label).
struct PestoCapsuleButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case secondary
        case destructive
        /// The answer to "Delete these clips?": a solid fill with a white label, so the one irreversible choice reads
        /// as strongly as the label of a cancel does.
        case confirmDestructive
    }

    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        Fill(configuration: configuration, role: role)
    }

    private struct Fill: View {
        let configuration: ButtonStyleConfiguration
        let role: Role
        @Environment(\.pestoAccentLabel) private var accentLabel
        @Environment(\.pestoAccent) private var accent
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
        @Environment(\.differentiateWithoutColorOverride) private var differentiateOverride
        @State private var isHovering = false

        private var emphasised: Bool {
            contrast == .increased || (differentiateOverride ?? systemDifferentiate)
        }

        private var pressed: Bool {
            configuration.isPressed
        }

        private var labelColor: Color {
            switch role {
            case .primary: accentLabel
            case .secondary: .primary
            case .destructive: .statusBad
            case .confirmDestructive: .white
            }
        }

        private var fill: Color {
            switch role {
            case .primary:
                accent.opacity(pressed ? 0.8 : 1)
            case .secondary:
                Color.primary.opacity(pressed ? 0.2 : isHovering ? 0.14 : 0.08)
            case .confirmDestructive:
                Color.statusBadFill.opacity(pressed ? 0.85 : 1)
            case .destructive:
                if pressed {
                    Color.statusBad.opacity(0.2)
                } else if isHovering {
                    Color.statusBad.opacity(0.12)
                } else {
                    Color.primary.opacity(0.08)
                }
            }
        }

        private var border: Color {
            switch role {
            case .primary:
                isHovering ? accentLabel.opacity(0.4) : .clear
            case .secondary:
                Color.primary.opacity(emphasised ? 0.45 : 0.14)
            case .destructive:
                Color.statusBad.opacity(emphasised || isHovering ? 0.45 : 0.14)
            case .confirmDestructive:
                isHovering ? Color.white.opacity(0.5) : .clear
            }
        }

        var body: some View {
            configuration.label
                .labelStyle(CapsuleLabelStyle())
                .foregroundStyle(labelColor)
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(border, lineWidth: emphasised ? 1 : 0.5)
                    .padding(role == .primary || role == .confirmDestructive ? 1 : 0))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { isHovering = $0 }
                .animation(Motion.animation(.pestoQuick), value: isHovering)
                .animation(Motion.animation(.pestoQuick), value: pressed)
        }
    }
}

private struct CapsuleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(.caption, weight: .semibold))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == PestoCapsuleButtonStyle {
    static func pestoCapsule(_ role: PestoCapsuleButtonStyle.Role) -> PestoCapsuleButtonStyle {
        PestoCapsuleButtonStyle(role: role)
    }
}
