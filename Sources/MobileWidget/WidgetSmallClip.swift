// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The small widget: the latest clip as its card would show it, the foot line at the bottom. A color fills the
/// widget (the view behind sets the swatch as the ground) and its text takes the card's black or white ink.
struct WidgetSmallClip: View {
    let clip: WidgetClip
    let now: Date
    let palette: WidgetPalette

    var body: some View {
        let ink = clip.colorHex.map(palette.ink(onSwatch:))
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if clip.kind == .image {
                    WidgetThumbnail(data: clip.thumbnail, side: nil)
                } else {
                    WidgetClipText(clip: clip, lines: clip.kind == .code ? 6 : 4, ink: ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .privacySensitive()
            WidgetFootLine(clip: clip, now: now, accent: palette.accent, ink: ink)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetClipSpeech.label(clip, now: now))
        .accessibilityHint("Copies this clip")
    }
}
