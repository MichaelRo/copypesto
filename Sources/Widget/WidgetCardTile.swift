// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// One clip as a Pesto card at widget scale: the card's white (white at 10 percent on a dark ground) with its
/// hairline, or the color itself, or the picture; the content set as the card sets it; one quiet foot line. In the
/// small widget the card is the whole widget (`isWholeWidget`), so it draws no edge of its own.
struct WidgetCardTile: View {
    let clip: WidgetClip
    let now: Date
    let palette: WidgetPalette
    var copied = false
    var isWholeWidget = false
    var isRoomy = false
    /// The app's icon from the snapshot (ADR 0074).
    var appIcon: Data?

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorSchemeContrast) private var contrast

    private static let corner: CGFloat = 12
    /// Under the foot line of a picture, so its white text reads on any picture.
    static let scrim = LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

    var body: some View {
        let ink = clip.colorHex.map(palette.ink(onSwatch:))
        VStack(alignment: .leading, spacing: 4) {
            if clip.kind == .image {
                Spacer(minLength: 0)
            } else {
                WidgetCardBody(clip: clip, ink: ink, isRoomy: isRoomy || isWholeWidget)
                    .frame(
                        maxWidth: .infinity, maxHeight: .infinity,
                        alignment: clip.kind == .color ? .bottomLeading : .topLeading
                    )
                    .privacySensitive()
            }
            WidgetFootLine(
                clip: clip, now: now, accent: palette.accent, ink: clip.kind == .image ? .white : ink, copied: copied,
                appIcon: renderingMode == .fullColor ? appIcon : nil
            )
        }
        .multilineTextAlignment(.leading)
        .padding(inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack {
                if !isWholeWidget {
                    ground
                    if clip.kind == .image { Self.scrim }
                }
                if let glow { WidgetGlow(glow: glow) }
            }
        }
        .clipShape(.rect(cornerRadius: isWholeWidget ? 0 : Self.corner, style: .continuous))
        .overlay {
            if !isWholeWidget, clip.colorHex == nil, clip.kind != .image {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 0.75)
            }
        }
        .foregroundStyle(Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copied ? String(localized: "Copied") : WidgetClipSpeech.label(clip, now: now))
    }

    /// The foot glow in the app's color, as Pesto's card draws it (ADR 0068): only in full color, where a tinted or
    /// clear Home Screen and the Mac's desktop would turn it into a grey smear, and never on a picture or a color.
    private var glow: CardGlow? {
        guard renderingMode == .fullColor, clip.kind != .image, clip.kind != .color else { return nil }
        return CardGlow.decide(
            colorHex: clip.sourceColorHex, themeAccentHex: palette.accentHex, isDark: palette.isDark, isGlass: false,
            increaseContrast: contrast == .increased, isSelected: false
        )
    }

    private var inset: CGFloat {
        isWholeWidget ? 0 : 10
    }

    @ViewBuilder
    private var ground: some View {
        if let hex = clip.colorHex, let color = WidgetPalette.color(hex) {
            color
        } else if clip.kind == .image {
            WidgetPicture(data: clip.thumbnail, sourceBundleID: clip.sourceBundleID).privacySensitive()
        } else {
            palette.card
        }
    }
}

/// A card's content for its kind: short text large, longer text in whole lines, a link's host large with its path
/// small, code in monospace, a color's hex in its ink, a file by its name.
struct WidgetCardBody: View {
    let clip: WidgetClip
    let ink: Color?
    let isRoomy: Bool

    var body: some View {
        switch clip.kind {
        case .url where clip.linkHost != nil:
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.linkHost ?? "")
                    .font((isRoomy ? Font.title3 : .headline).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let path = clip.linkPath {
                    Text(path).font(.caption2).foregroundStyle(Color.secondary).lineLimit(isRoomy ? 3 : 2)
                }
            }
        case .color:
            Text(clip.colorHex.map { "#\($0)" } ?? clip.text)
                .font((isRoomy ? Font.title2 : .headline).monospaced().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(ink ?? Color.primary)
        case .code:
            Text(clip.text).font(.caption2.monospaced()).lineLimit(8)
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "doc").font(.title3).foregroundStyle(Color.secondary).accessibilityHidden(true)
                Text(clip.text).font(.footnote.weight(.medium)).lineLimit(3)
            }
        default:
            if isShort {
                Text(clip.text)
                    .font((isRoomy ? Font.title3 : .headline).weight(.semibold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
            } else {
                Text(clip.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(isRoomy ? .subheadline : .footnote)
                    .lineLimit(8)
            }
        }
    }

    private var isShort: Bool {
        clip.text.count <= CardTreatment.shortTextLimit && !clip.text.contains(where: \.isNewline)
    }
}
