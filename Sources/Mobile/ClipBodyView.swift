// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The clip's content in the detail view: selectable text, the picture, the link, the color. A covered clip shows its
/// mask (or, after Show, the start of its text) and nothing else.
struct ClipBodyView: View {
    let item: ClipboardItem
    let content: ClipContent?
    let concealment: CardConcealment
    let revealedText: String?

    var body: some View {
        if concealment.isConcealed {
            covered
        } else if let revealedText {
            selectable(revealedText, monospaced: true)
        } else {
            uncovered
        }
    }

    private var covered: some View {
        let summary = ClipSummary.make(item, concealment: concealment)
        return Label(summary.title, systemImage: item.sensitivityRaw != nil ? "lock" : "eye.slash")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var uncovered: some View {
        switch item.type {
        case .image:
            ClipThumbnail(itemID: item.id, byteSize: item.byteSize, maxPixel: 2048)
                .frame(maxWidth: .infinity, minHeight: 160)
                .clipShape(.rect(cornerRadius: 10))
        case .url:
            link
        case .color:
            color
        case .file:
            let urls = FileClip.urls(from: item.displayPreviewText)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(urls, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: "doc")
                }
            }
        case .code:
            selectable(content?.plainText ?? item.displayPreviewText, monospaced: true)
        case .text:
            selectable(content?.plainText ?? item.displayPreviewText, monospaced: false)
        }
    }

    @ViewBuilder
    private var link: some View {
        if case let .link(url, text) = content {
            VStack(alignment: .leading, spacing: 6) {
                if let site = item.ogSiteName { Text(site).font(.caption).foregroundStyle(.secondary) }
                Link(item.ogTitle ?? url.host() ?? text, destination: url)
                    .font(.headline)
                selectable(text, monospaced: false)
                    .font(.subheadline)
            }
        } else {
            selectable(item.displayPreviewText, monospaced: false)
        }
    }

    private var color: some View {
        let text = item.gridPreview
        let parsed = ColorLiteralParser.firstColor(in: text)
        return VStack(alignment: .leading, spacing: 10) {
            if let parsed {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: parsed.alpha))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator) }
                    .frame(height: 120)
                    .accessibilityHidden(true)
            }
            selectable(text, monospaced: true)
        }
    }

    private func selectable(_ text: String, monospaced: Bool) -> some View {
        Text(text)
            .font(monospaced ? .body.monospaced() : .body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
