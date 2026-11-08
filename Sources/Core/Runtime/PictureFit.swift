// SPDX-License-Identifier: MIT

/// Whether a picture card fills the card bounds edge-to-edge or falls back to fitted layout for invalid dimensions.
public enum PictureFit: Equatable, Sendable {
    case fill
    case fit

    public static func decide(aspectRatio: Double) -> PictureFit {
        aspectRatio.isFinite && aspectRatio > 0 ? .fill : .fit
    }
}
