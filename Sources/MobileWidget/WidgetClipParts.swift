// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The quiet line under a clip: where it came from and its age as the card writes it, then the pin in the accent.
struct WidgetFootLine: View {
    let clip: WidgetClip
    let now: Date
    let accent: Color
    var ink: Color?

    var body: some View {
        HStack(spacing: 4) {
            Text(WidgetClipSpeech.foot(clip, now: now))
                .lineLimit(1)
            if clip.isPinned {
                Image(systemName: "pin.fill")
                    .imageScale(.small)
                    .foregroundStyle(ink ?? accent)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption2)
        .foregroundStyle(ink.map { $0.opacity(0.8) } ?? Color.secondary)
    }
}

/// A picture's thumbnail, cropped to a rounded square of `side` or filling what it is given when `side` is nil; the
/// picture symbol when there is none.
struct WidgetThumbnail: View {
    let data: Data?
    let side: CGFloat?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: side, height: side)
        .frame(maxWidth: side == nil ? .infinity : nil, maxHeight: side == nil ? .infinity : nil)
        .clipShape(.rect(cornerRadius: side == nil ? 10 : 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A color clip's swatch in a row, with the card's hairline.
struct WidgetSwatch: View {
    let hex: String
    let side: CGFloat
    let palette: WidgetPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(WidgetPalette.color(hex) ?? .clear)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(
                palette.hairline,
                lineWidth: 0.75
            ))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// What VoiceOver and the foot line say about a clip.
enum WidgetClipSpeech {
    static func foot(_ clip: WidgetClip, now: Date) -> String {
        let age = CardAge.text(interval: now.timeIntervalSince(clip.date))
        return [clip.source, age].compactMap(\.self).joined(separator: " \u{00B7} ")
    }

    static func label(_ clip: WidgetClip, now: Date) -> String {
        let shown: String = switch clip.kind {
        case .url: clip.linkHost ?? clip.text
        case .color: clip.colorHex.map { "#\($0)" } ?? clip.text
        default: clip.text
        }
        let age = CardAge.spoken(interval: now.timeIntervalSince(clip.date))
        let pinned = clip.isPinned ? String(localized: "Pinned") : nil
        return [clip.kind.presentation.label, shown, clip.source, age, pinned].compactMap(\.self)
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
