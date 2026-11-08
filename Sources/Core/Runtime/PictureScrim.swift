// SPDX-License-Identifier: MIT

/// The surface-harmonized wash under header text on a picture or rich link card, and the arithmetic that keeps that
/// text readable over the worst-case picture (pure white in dark appearance, pure black in light appearance).
public enum PictureScrim {
    public static let topOpacity = 0.90
    public static let headerBottomOpacity = 0.84
    public static let fadeHeight = 40.0
    public static let nameOpacity = 1.0
    public static let ageOpacity = 0.85
    public static let pillOpacity = 0.85
    public static let pasteCountOpacity = 1.0
    public static let badgeOpacity = 1.0

    public static func opacity(atHeight height: Double) -> Double {
        let header = Double(CardLayout.headerHeight)
        guard height > 0 else { return topOpacity }
        if height <= header {
            let t = height / header
            return topOpacity + (headerBottomOpacity - topOpacity) * t
        }
        guard height < header + fadeHeight else { return 0 }
        return headerBottomOpacity * (1 - (height - header) / fadeHeight)
    }

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
