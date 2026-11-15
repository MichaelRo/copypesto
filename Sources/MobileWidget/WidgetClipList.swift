// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// The medium and large widgets: one row per clip, each a link that copies it. The large one sets each row on the
/// card's white (or white at 10 percent) with its hairline; the medium one has room only for dividers.
struct WidgetClipList: View {
    let clips: [WidgetClip]
    let now: Date
    let palette: WidgetPalette
    let roomy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: roomy ? 6 : 0) {
            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                if !roomy, index > 0 { Divider().overlay(palette.hairline) }
                Link(destination: WidgetLink.url(for: clip.id)) {
                    WidgetClipRow(clip: clip, now: now, palette: palette)
                        .padding(.horizontal, roomy ? 10 : 0)
                        .padding(.vertical, roomy ? 7 : 5)
                        .frame(maxWidth: .infinity, maxHeight: roomy ? .infinity : nil, alignment: .leading)
                        .background {
                            if roomy {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(palette.hairline, lineWidth: 0.75)
                                    )
                            }
                        }
                }
            }
            if !roomy { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One clip in a row: a thumbnail or swatch when it has one, its text in the card's style for its kind, and the foot
/// line.
struct WidgetClipRow: View {
    let clip: WidgetClip
    let now: Date
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 10) {
            if clip.kind == .image {
                WidgetThumbnail(data: clip.thumbnail, side: 34)
                    .privacySensitive()
            } else if let hex = clip.colorHex {
                WidgetSwatch(hex: hex, side: 34, palette: palette)
                    .privacySensitive()
            }
            VStack(alignment: .leading, spacing: 1) {
                WidgetClipText(clip: clip, lines: 1)
                    .privacySensitive()
                WidgetFootLine(clip: clip, now: now, accent: palette.accent)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetClipSpeech.label(clip, now: now))
        .accessibilityHint("Copies this clip")
    }
}

/// A clip's text as its card sets it: a link's host leads with its path small, code in monospace, a color by its
/// hex, a file by its name, a picture by its description.
struct WidgetClipText: View {
    let clip: WidgetClip
    let lines: Int
    var ink: Color?

    var body: some View {
        switch clip.kind {
        case .url where clip.linkHost != nil:
            let host = Text(clip.linkHost ?? "")
                .font(lines > 1 ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
            if lines > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    host.lineLimit(1).minimumScaleFactor(0.7)
                    if let path = clip.linkPath {
                        Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(lines - 1)
                    }
                }
                .foregroundStyle(ink ?? .primary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    host.lineLimit(1).layoutPriority(1)
                    if let path = clip.linkPath {
                        Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .foregroundStyle(ink ?? .primary)
            }
        case .code:
            text.font(.footnote.monospaced())
        case .color:
            Text(clip.colorHex.map { "#\($0)" } ?? clip.text)
                .font(.subheadline.monospaced().weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(ink ?? .primary)
        case .file:
            Label(clip.text, systemImage: "doc").font(.subheadline).lineLimit(lines)
        default:
            text.font(isShort && lines > 1 ? .title3.weight(.semibold) : .subheadline)
        }
    }

    private var text: some View {
        Text(clip.text.isEmpty ? clip.kind.presentation.label : Self.flattened(clip.text, lines: lines))
            .lineLimit(lines)
            .foregroundStyle(ink ?? .primary)
    }

    private var isShort: Bool {
        clip.text.count <= CardTreatment.shortTextLimit && !clip.text.contains(where: \.isNewline)
    }

    /// A one-line row shows the first lines run together, as the card's preview does.
    static func flattened(_ text: String, lines: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lines == 1 else { return trimmed }
        return trimmed.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
