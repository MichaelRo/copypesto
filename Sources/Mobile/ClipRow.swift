// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct ClipRow: View {
    let item: ClipboardItem
    @Environment(MobileAppState.self) private var appState
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        let summary = ClipSummary.make(item, concealment: appState.secretReveal.concealment(for: item))
        HStack(alignment: .top, spacing: 12) {
            visual(summary)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(item.type == .code && !summary.isCovered ? .body.monospaced() : .body)
                    .lineLimit(3)
                if let detail = summary.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if let source = summary.source {
                        Text(source)
                        Text(verbatim: "·").accessibilityHidden(true)
                    }
                    Text(item.timestamp, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if summary.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(accent)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(MobileAccessibilityID.clipRow)
    }

    @ViewBuilder
    private func visual(_ summary: ClipSummary) -> some View {
        switch summary.visual {
        case .picture:
            ClipThumbnail(itemID: item.id, byteSize: item.byteSize, maxPixel: ClipThumbnail.rowPixel)
                .background(Color.secondary.opacity(0.08))
        case let .swatch(color):
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
                .accessibilityHidden(true)
        case let .symbol(name):
            Image(systemName: name)
                .font(.title3)
                .foregroundStyle(summary.isCovered ? Color.secondary : accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
                .accessibilityHidden(true)
        }
    }
}
