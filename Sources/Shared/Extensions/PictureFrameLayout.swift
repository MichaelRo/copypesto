// SPDX-License-Identifier: MIT
import SwiftUI

/// Places its one subview at the rect `frame` gives for the size offered, so a fitted picture sits where Core's
/// `PictureFrame` says on every card size without a `GeometryReader` (ADR 0080).
struct PictureFrameLayout: Layout {
    let frame: @Sendable (CGSize) -> CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let rect = frame(bounds.size)
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(rect.size)
            )
        }
    }
}
