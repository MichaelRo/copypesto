// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct PlainTextBody: View {
    let text: String
    let isCode: Bool
    let metrics: CardMetrics

    var body: some View {
        Text(CardPreviewText.display(text))
            .font(isCode ? .footnote.monospaced() : .callout)
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(metrics.lines(isCode ? .footnote : .callout))
    }
}

struct LargeTextBody: View {
    let text: String
    let points: Double
    let metrics: CardMetrics

    var body: some View {
        Text(text)
            .scaledFont(size: metrics.points(points), weight: .semibold, maxScale: CardMetrics.maxTextScale)
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(CardTreatment.maxLines(forPoints: points))
            .minimumScaleFactor(0.75)
    }
}

struct LinkBody: View {
    let link: LinkDisplay
    let metrics: CardMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(link.host)
                .scaledFont(
                    size: metrics.points(LinkDisplay.hostPoints(forLength: link.host.count)),
                    weight: .semibold,
                    maxScale: CardMetrics.maxTextScale
                )
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(LinkDisplay.hostMinimumScale)
            if !link.rest.isEmpty {
                Text(link.rest)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
        }
    }
}

struct FileBody: View {
    let preview: String

    var body: some View {
        let files = FileClip.summary(of: preview)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(files.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
                if !files.subtitle.isEmpty {
                    Text(files.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}
