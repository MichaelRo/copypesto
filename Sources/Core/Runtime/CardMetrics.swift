// SPDX-License-Identifier: MIT
import CoreGraphics

/// How big a shelf card is for a chosen width: the height always runs 20 pt below the width, which is how the three
/// named
/// sizes (160, 180 and 200 wide) were drawn, so the slider and the tiles agree.
public enum CardMetrics {
    /// Widths a stored setting may hold (an older build allowed 150).
    public static let widthRange = 150...240
    /// What the slider covers, with a labelled tick at each recommended width: small, medium, large.
    public static let sliderRange = 160...240
    public static let recommendedWidths = [160, 200, 240]

    /// "Small", "Medium" or "Large" for a recommended width, nil for anything between.
    public static func recommendedName(forWidth width: Int) -> String? {
        switch width {
        case recommendedWidths[0]: "Small"
        case recommendedWidths[1]: "Medium"
        case recommendedWidths[2]: "Large"
        default: nil
        }
    }

    public static func dimensions(width: Int) -> CGSize {
        let clamped = min(max(width, widthRange.lowerBound), widthRange.upperBound)
        return CGSize(width: clamped, height: clamped - 20)
    }

    /// The preset a width is close enough to land on while a slider is released, or the width itself.
    public static func snap(_ width: Int, to presets: [Int], tolerance: Int = 6) -> Int {
        presets.min { abs($0 - width) < abs($1 - width) }.flatMap { abs($0 - width) <= tolerance ? $0 : nil } ?? width
    }
}
