// SPDX-License-Identifier: MIT

/// The dark wash under white text on a picture card, and the arithmetic that keeps that text readable over the
/// brightest picture there can be (white). The wash is solid across the header band, where the text is, and fades
/// below it, so the picture is clear beneath.
public enum PictureScrim {
    public static let topOpacity = 0.6
    public static let fadeHeight = 22.0
    public static let nameOpacity = 1.0
    public static let ageOpacity = 0.85
    public static let pillOpacity = 0.6

    public static func opacity(atHeight height: Double) -> Double {
        let solid = Double(CardLayout.headerHeight)
        guard height > solid else { return topOpacity }
        guard height < solid + fadeHeight else { return 0 }
        return topOpacity * (1 - (height - solid) / fadeHeight)
    }

    /// WCAG contrast of white text at `textOpacity` over a white picture covered by black at `coverOpacity`.
    public static func worstCaseContrast(coverOpacity: Double = topOpacity, textOpacity: Double) -> Double {
        let ground = 1 - coverOpacity
        let text = textOpacity + (1 - textOpacity) * ground
        let light = HexColorComponents(red: text, green: text, blue: text).luminance
        let dark = HexColorComponents(red: ground, green: ground, blue: ground).luminance
        return (light + 0.05) / (dark + 0.05)
    }
}
