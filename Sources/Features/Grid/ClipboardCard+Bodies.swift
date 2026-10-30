// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

extension ClipboardCard {
    var imageBody: some View {
        Color.clear
            .overlay {
                if let shown = shownThumbnail {
                    let img = shown.image
                    if shown.isAnimated {
                        AnimatedImageView(image: img, animates: playsAnimations)
                    } else {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                } else {
                    Color.white.opacity(0.06)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 26))
                                .foregroundStyle(AdaptiveContrast.quiet(contrast))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var colorBody: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(detectedColor ?? Color.purple.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
    }

    var isGlyphCard: Bool {
        item.type == .text && !isRenamingTitle && item.sensitivity == nil
            && CardPreviewText.isSingleGlyph(CardPreviewText.display(item.gridPreview))
    }

    var glyphBody: some View {
        Text(CardPreviewText.display(item.gridPreview))
            .scaledFont(size: bodySize(64), maxScale: 1.3)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var urlImageBody: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay {
                    if let img = urlOGImage {
                        if urlOGImageIsAnimated {
                            AnimatedImageView(image: img, animates: playsAnimations)
                        } else {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                }
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 58)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                if let title = item.ogTitle ?? item.customTitle {
                    Text(title)
                        // Text size capped: fills a fixed-size card's image scrim.
                            .scaledFont(size: 11, weight: .semibold, maxScale: 1.3)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .truncationMode(.tail)
                }
                HStack(spacing: 4) {
                    if let favicon = urlFavicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .frame(width: 12, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(item.ogSiteName ?? URL(string: item.displayPreviewText)?.host ?? item.displayPreviewText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
