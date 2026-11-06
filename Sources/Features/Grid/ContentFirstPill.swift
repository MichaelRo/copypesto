// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The small outlined label at the foot of a picture or color card (the shortcut number, GIF). On a picture it sits on
/// a dark translucent ground strong enough for white text over the brightest picture (`PictureScrim.pillOpacity`);
/// on a color it is the fill's own ink with an outline only.
struct ContentFirstPill: View {
    let text: String
    let ink: Color
    let onPicture: Bool

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                if onPicture {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black.opacity(PictureScrim.pillOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(ink.opacity(0.55), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
