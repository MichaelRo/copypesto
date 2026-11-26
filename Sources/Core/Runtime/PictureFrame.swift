// SPDX-License-Identifier: MIT
import CoreGraphics

/// Where a picture shown whole sits on its card (ADR 0080). It is never shrunk to keep a fixed band free for the line
/// of facts: it fits the card less `minimumBand`, so a tall one keeps nearly the whole height and only its last few
/// points pass under the pills (which carry their own ground, `PictureScrim`). Height left over goes below the
/// picture first, up to `footerBand`, so a wide picture clears the facts; anything beyond that is shared top and
/// bottom.
public enum PictureFrame {
    /// The least a fitted picture leaves under itself: the pills then cover at most their own lower half of it.
    public static let minimumBand: CGFloat = 18
    /// A picture smaller than the card is drawn at most this many points per pixel.
    public static let smallPictureScale: CGFloat = 2
    /// At or under this many pixels on its longer side a picture is pixel art or an icon, drawn with hard edges.
    public static let sharpPixelLimit: CGFloat = 64

    public static func fitted(
        aspectRatio: Double, in card: CGSize, footerBand: CGFloat, pixelSize: CGSize? = nil
    )
    -> CGRect {
        guard card.width > 0, card.height > 0 else { return .zero }
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? CGFloat(aspectRatio) : 1
        let boxHeight = max(card.height - minimumBand, 1)
        var size = aspect >= card.width / boxHeight
            ? CGSize(width: card.width, height: card.width / aspect)
            : CGSize(width: boxHeight * aspect, height: boxHeight)
        if let pixelSize, PictureFit.isSmall(pixelSize, on: card), pixelSize.width > 0, pixelSize.height > 0 {
            let cap = min(
                pixelSize.width * smallPictureScale / size.width, pixelSize.height * smallPictureScale / size.height
            )
            if cap < 1 { size = CGSize(width: size.width * cap, height: size.height * cap) }
        }
        let free = card.height - size.height
        let below = min(free, max(free / 2, footerBand))
        return CGRect(x: (card.width - size.width) / 2, y: free - below, width: size.width, height: size.height)
    }

    public static func drawsPixelsSharp(pixelSize: CGSize) -> Bool {
        pixelSize.width > 0 && pixelSize.height > 0 && max(pixelSize.width, pixelSize.height) <= sharpPixelLimit
    }
}
