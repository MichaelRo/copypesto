// SPDX-License-Identifier: MIT
import SwiftUI

/// A filled button in the person's accent. The system prominent style prints white on it, which is about 2:1 on the
/// light green of dark mode; the label colour comes from `pestoAccentLabel`.
struct PestoProminentButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        Fill(configuration: configuration, controlSize: controlSize)
    }

    private struct Fill: View {
        let configuration: ButtonStyleConfiguration
        let controlSize: ControlSize
        @Environment(\.pestoAccent) private var accent
        @Environment(\.pestoAccentLabel) private var label
        @Environment(\.isEnabled) private var isEnabled

        private var metrics: Metrics {
            switch controlSize {
            case .mini: Metrics(font: .caption, horizontal: 8, vertical: 2, radius: 5)
            case .small: Metrics(font: .callout, horizontal: 10, vertical: 3, radius: 6)
            case .large: Metrics(font: .body, horizontal: 16, vertical: 7, radius: 9)
            default: Metrics(font: .body, horizontal: 12, vertical: 4, radius: 7)
            }
        }

        var body: some View {
            let size = metrics
            configuration.label
                .font(size.font.weight(.medium))
                .foregroundStyle(label)
                .padding(.horizontal, size.horizontal)
                .padding(.vertical, size.vertical)
                .background(accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: size.radius))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(.rect(cornerRadius: size.radius))
        }
    }
}

private struct Metrics {
    let font: Font
    let horizontal: CGFloat
    let vertical: CGFloat
    let radius: CGFloat
}

extension ButtonStyle where Self == PestoProminentButtonStyle {
    static var pestoProminent: PestoProminentButtonStyle {
        PestoProminentButtonStyle()
    }
}
