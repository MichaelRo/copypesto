// SPDX-License-Identifier: MIT
import SwiftUI

/// A text button in the person's accent. The system link style draws its own blue and ignores `.tint`.
struct PestoLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.pestoAccent) private var accent

        var body: some View {
            configuration.label
                .foregroundStyle(accent)
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

extension ButtonStyle where Self == PestoLinkButtonStyle {
    static var pestoLink: PestoLinkButtonStyle {
        PestoLinkButtonStyle()
    }
}
