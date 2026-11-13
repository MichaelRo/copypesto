// SPDX-License-Identifier: MIT

/// The surface-harmonized ground under text laid over a picture (the line of facts, a rich link's title), and the
/// arithmetic that keeps that text readable over the worst-case picture (pure white in dark appearance, pure black in
/// light appearance). A picture card has no header and no scrim since ADR 0044; what is left is the pill ground and the
/// link picture's gradient.
public enum PictureScrim {
    public static let topOpacity = 0.90
    public static let headerBottomOpacity = 0.84
    public static let nameOpacity = 1.0
    public static let ageOpacity = 0.85
    public static let pillOpacity = 0.85
    public static let badgeOpacity = 1.0

    /// WCAG contrast of `textHex` at `textOpacity` over a picture covered by `coverHex` at `coverOpacity`.
    public static func worstCaseContrast(
        coverHex: String = BrandPalette.darkSurface,
        coverOpacity: Double = headerBottomOpacity,
        textHex: String = "FFFFFF",
        textOpacity: Double,
        pictureIsBright: Bool = true
    )
    -> Double {
        let pictureHex = pictureIsBright ? "FFFFFF" : "000000"
        let groundHex = ContrastRatio.blend(coverHex, over: pictureHex, alpha: coverOpacity)
        let drawnTextHex = ContrastRatio.blend(textHex, over: groundHex, alpha: textOpacity)
        return ContrastRatio.between(drawnTextHex, groundHex)
    }
}
