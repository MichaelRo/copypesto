// SPDX-License-Identifier: MIT

/// The text color on a card filled with a color: black or white, whichever reads better on the fill.
public enum CardInk: Equatable, Sendable {
    case black
    case white

    /// A fill that is see-through is judged over the backdrop behind it (black in a dark card, white in a light one).
    public static func forFill(_ fill: HexColorComponents, backdropIsDark: Bool) -> CardInk {
        let behind = backdropIsDark ? 0.0 : 1.0
        func over(_ channel: Double) -> Double {
            channel * fill.alpha + behind * (1 - fill.alpha)
        }
        let luminance = HexColorComponents(red: over(fill.red), green: over(fill.green), blue: over(fill.blue))
            .luminance
        let whiteContrast = 1.05 / (luminance + 0.05)
        let blackContrast = (luminance + 0.05) / 0.05
        return whiteContrast >= blackContrast ? .white : .black
    }

    /// The color's text is the loudest thing on its card up to a `#RRGGBBAA`; a longer function such as `rgba()` is
    /// set small enough to wrap on two lines.
    public static func labelPoints(forLength length: Int) -> Double {
        length <= 9 ? 26 : 15
    }
}
