// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Reduce-Transparency-aware replacements for `.ultraThinMaterial`.
///
/// System materials (`.ultraThinMaterial`) and Liquid Glass (`.glassEffect`) already respond
/// to the accessibility "Reduce Transparency" setting. Pesto's own low-opacity fills and the
/// mesh-glow backdrop do not, so translucent panels can still leave text hard to read over a
/// busy desktop when a user asks for reduced transparency (or dials up macOS 26+'s transparency
/// intensity). These helpers swap the material for an opaque, theme-aware surface in that case,
/// keeping every translucent surface legible with one shared decision point.
extension Color {
    /// Opaque, theme-adaptive stand-in for a frosted panel when transparency is reduced.
    static var opaqueSurface: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

extension EnvironmentValues {
    /// Preview/test-only override for the reduced-transparency branch below.
    ///
    /// SwiftUI exposes `\.accessibilityReduceTransparency` as a read-only `KeyPath` (it reads
    /// live system state directly), so it cannot be injected via `.environment(\.accessibilityReduceTransparency,
    /// _)` the way ordinary environment values can. This override key is a normal writable entry
    /// that snapshot tests set instead, letting them force the opaque-fallback path without
    /// touching System Settings. Production code never sets it.
    @Entry var reduceTransparencyOverride: Bool?
}

extension View {
    /// `.background(.ultraThinMaterial)`, or an opaque surface under Reduce Transparency.
    func adaptiveMaterialBackground() -> some View {
        modifier(AdaptiveMaterialBackground(shape: nil))
    }

    /// `.background(.ultraThinMaterial, in: shape)`, or an opaque surface under Reduce Transparency.
    func adaptiveMaterialBackground(in shape: some Shape) -> some View {
        modifier(AdaptiveMaterialBackground(shape: AnyShape(shape)))
    }
}

extension Shape {
    /// A flat translucent fill for a card that sits on the shelf's glass. A card on its own blur costs a backdrop
    /// sample per card per frame while the row scrolls; this is one colour, and the shelf behind already blurs.
    func adaptiveCardFill() -> some View {
        AdaptiveCardFill(shape: self)
    }

    /// `fill(.ultraThinMaterial)`, or an opaque surface fill under Reduce Transparency.
    func adaptiveMaterialFill() -> some View {
        AdaptiveMaterialFill(shape: self)
    }
}

private struct AdaptiveMaterialBackground: ViewModifier {
    let shape: AnyShape?
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    func body(content: Content) -> some View {
        switch (shape, reduceTransparency) {
        case let (shape?, true): content.background(Color.opaqueSurface, in: shape)
        case let (shape?, false): content.background(.ultraThinMaterial, in: shape)
        case (nil, true): content.background(Color.opaqueSurface)
        case (nil, false): content.background(.ultraThinMaterial)
        }
    }
}

private struct AdaptiveMaterialFill<S: Shape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        shape.fill(
            reduceTransparency
                ? AnyShapeStyle(Color.opaqueSurface)
                : AnyShapeStyle(.ultraThinMaterial)
        )
    }
}

private struct AdaptiveCardFill<S: Shape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        shape.fill(
            reduceTransparency
                ? Color.opaqueSurface
                : Color.white.opacity(colorScheme == .dark ? 0.10 : 0.58)
        )
    }
}
