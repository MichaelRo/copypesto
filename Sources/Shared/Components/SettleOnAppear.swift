// SPDX-License-Identifier: MIT
import SwiftUI

/// One small, quiet motion when a picture first appears: the leaf sways and comes to rest, the jar drops in and lands.
/// It happens once per appearance, ends where the picture normally sits, and does not happen at all under Reduce Motion
/// (the picture is simply there). Used on illustrations, never on controls.
struct SettleOnAppear: ViewModifier {
    enum Style {
        case sway
        case hop

        var animation: Animation {
            switch self {
            case .sway: .spring(response: 0.7, dampingFraction: 0.35)
            case .hop: .spring(response: 0.45, dampingFraction: 0.5).delay(0.2)
            }
        }
    }

    let style: Style
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(style == .sway && !settled ? -4 : 0), anchor: .bottom)
            .offset(y: style == .hop && !settled ? -8 : 0)
            .onAppear {
                withAnimation(Motion.animation(style.animation)) { settled = true }
            }
    }
}

extension View {
    func settleOnAppear(_ style: SettleOnAppear.Style) -> some View {
        modifier(SettleOnAppear(style: style))
    }
}
