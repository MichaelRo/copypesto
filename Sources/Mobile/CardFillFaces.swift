// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// A picture fills its card edge to edge when its shape is near the card's (a very tall one from its top); otherwise it
/// is
/// shown whole over a blurred, darkened still copy of itself, placed by `PictureFrame` (ADR 0041, ADR 0080). The line
/// of facts sits on pills, never on a scrim.
struct PictureCardFace<Foot: View>: View {
    let image: UIImage?
    let fit: PictureFit
    var pixelSize: CGSize?
    var animation: GIFFrames.Animation?
    var title: String?
    var subtitle: String?
    @ViewBuilder let foot: () -> Foot
    @Environment(\.pestoSurface) private var surface

    var body: some View {
        ZStack(alignment: .bottom) {
            picture
            VStack(alignment: .leading, spacing: 4) {
                if title != nil || subtitle != nil {
                    VStack(alignment: .leading, spacing: 1) {
                        if let title {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        surface.opacity(PictureScrim.pillOpacity),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                    )
                }
                foot()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            if fit.fills {
                filled(image)
            } else {
                let aspect = Double(image.size.width / max(image.size.height, 1))
                let band: CGFloat = title == nil && subtitle == nil ? 30 : 54
                let pixels = pixelSize
                ZStack {
                    Color.clear
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipped()
                        .contentShape(.rect)
                        .blur(radius: 14, opaque: true)
                        .overlay(Color.black.opacity(0.35))
                        .drawingGroup(opaque: true)
                    let placement = PictureFrameLayout { size in
                        PictureFrame.fitted(aspectRatio: aspect, in: size, footerBand: band, pixelSize: pixels)
                    }
                    placement {
                        still(image, fills: true)
                    }
                }
                .contentShape(.rect)
            }
        } else {
            PicturePlaceholder()
        }
    }

    private func filled(_ image: UIImage) -> some View {
        Color.clear
            .overlay(alignment: fit == .fillFromTop ? .top : .center) { still(image, fills: true) }
            .clipped()
            .contentShape(.rect)
    }

    @ViewBuilder
    private func still(_ image: UIImage, fills: Bool) -> some View {
        if let animation {
            AnimatedPicture(animation: animation, fills: fills)
        } else if pixelSize.map(PictureFrame.drawsPixelsSharp) == true {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFill()
        } else if fills {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(uiImage: image).resizable().scaledToFit()
        }
    }
}
