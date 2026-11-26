// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The quiet line at a card's foot: where it came from and its age as the card writes it, then the pin in the accent;
/// for a moment after an in-place copy, Copied in the accent instead.
struct WidgetFootLine: View {
    let clip: WidgetClip
    let now: Date
    let accent: Color
    var ink: Color?
    var copied = false
    var appIcon: Data?

    var body: some View {
        HStack(spacing: 4) {
            if !copied, let appIcon, let image = PlatformImage(data: appIcon) {
                WidgetPicture.image(image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 13, height: 13)
                    .clipShape(.rect(cornerRadius: 3, style: .continuous))
                    .accessibilityHidden(true)
            }
            if copied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(ink ?? accent)
            } else {
                ViewThatFits(in: .horizontal) {
                    Text(WidgetClipSpeech.foot(clip, now: now))
                    Text(CardAge.text(interval: now.timeIntervalSince(clip.date)))
                }
                .foregroundStyle(ink.map { $0.opacity(0.8) } ?? Color.secondary)
                if clip.isPinned {
                    Image(systemName: "pin.fill")
                        .imageScale(.small)
                        .foregroundStyle(ink ?? accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }
}

/// A picture as its card draws it: filling the tile when its shape is near a card's (ADR 0041), otherwise whole over a
/// blurred, darkened copy of itself; the picture symbol when the snapshot has no thumbnail.
struct WidgetPicture: View {
    let data: Data?

    var body: some View {
        if let data, let image = PlatformImage(data: data) {
            let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
            if CardTreatment.pictureFillRange.contains(aspect) {
                Color.clear
                    .overlay { Self.image(image).resizable().scaledToFill() }
                    .clipped()
                    .contentShape(.rect)
            } else {
                Color.black
                    .overlay { Self.image(image).resizable().scaledToFill().blur(radius: 14).opacity(0.7) }
                    .overlay { Self.image(image).resizable().scaledToFit() }
                    .clipped()
                    .contentShape(.rect)
            }
        } else {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension WidgetPicture {
    static func image(_ image: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
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

    static func hint(_ tap: WidgetTap, kind: ClipboardType) -> String {
        switch tap {
        case .copyInPlace: String(localized: "Copies this clip")
        case let .link(url):
            switch WidgetLink.target(in: url)?.action {
            case .copy: String(localized: "Opens Pesto and copies this clip")
            case .open where kind == .url: String(localized: "Opens this link")
            default: String(localized: "Opens this clip in Pesto")
            }
        }
    }
}
