// SPDX-License-Identifier: MIT
import SwiftUI

/// Drop-in replacement for `.font(.system(size:weight:design:))` that follows the system text size: checked by hand on
/// 2026-10-22 (Settings > Accessibility > Display > Text size at the largest grows Pesto's text without clipping).
/// A hosted test cannot show it, because `.dynamicTypeSize` does not change a `@ScaledMetric` on macOS.
///
/// `ClipboardCard`'s cards have a fixed pixel size (compact/standard/large, chosen in Settings),
/// so text inside them uses `maxScale` to cap growth rather than let the largest accessibility
/// sizes overflow a fixed-height card; everywhere else (banners, toasts, popovers, Settings,
/// onboarding, the lock screen, the AI panel) scales without a cap.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let baseSize: CGFloat
    private let maxScale: CGFloat?
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, maxScale: CGFloat? = nil) {
        _scaledSize = ScaledMetric(wrappedValue: size)
        baseSize = size
        self.maxScale = maxScale
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(
            size: ScaledFont.resolvedSize(scaled: scaledSize, base: baseSize, maxScale: maxScale),
            weight: weight,
            design: design
        ))
    }

    /// The cap decision, pulled out of the view body so it is testable without rendering
    /// (`@ScaledMetric` itself needs a live environment to read the system text size from).
    static func resolvedSize(scaled: CGFloat, base: CGFloat, maxScale: CGFloat?) -> CGFloat {
        guard let maxScale else { return scaled }
        return min(scaled, base * maxScale)
    }
}

extension View {
    /// `.font(.system(size:weight:design:))`, scaled with the system text size.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }

    /// Same as `scaledFont`, but growth stops at `baseSize * maxScale` — for text inside a
    /// fixed-size card, where unbounded growth would overflow the card rather than wrap or scroll.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        maxScale: CGFloat
    )
    -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, maxScale: maxScale))
    }
}
