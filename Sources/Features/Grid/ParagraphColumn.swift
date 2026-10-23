// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Lays a text card's paragraphs and the gaps between them top to bottom inside a height budget: whole paragraphs while
/// they fit, then the paragraph that crosses the budget gets what is left (Text cuts it at a whole line with an
/// ellipsis), and nothing after it is drawn.
struct ParagraphColumn: Layout {
    var budget: CGFloat

    private struct IsGap: LayoutValueKey {
        static let defaultValue = false
    }

    static func gap() -> some View {
        ParagraphGap().layoutValue(key: IsGap.self, value: true)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let placed = arrange(width: proposal.width ?? 200, subviews: subviews)
        return CGSize(width: proposal.width ?? placed.width, height: placed.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let width = bounds.width
        let placed = arrange(width: width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            if let frame = placed.frames[index] {
                subview.place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(width: width, height: frame.height)
                )
            } else {
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.maxY + 10_000), proposal: .zero)
            }
        }
    }

    private struct Arrangement {
        var frames: [CGRect?]
        var height: CGFloat
        var width: CGFloat
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        var frames: [CGRect?] = []
        var y: CGFloat = 0
        var widest: CGFloat = 0
        var full = false
        for subview in subviews {
            if full { frames.append(nil)
                continue
            }
            if subview[IsGap.self] {
                let gap = CardLayout.paragraphGap
                if y + gap >= budget { full = true
                    frames.append(nil)
                    continue
                }
                frames.append(CGRect(x: 0, y: y, width: width, height: gap))
                y += gap
                continue
            }
            let natural = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let remaining = budget - y
            let size = natural.height <= remaining
                ? natural
                : subview.sizeThatFits(ProposedViewSize(width: width, height: remaining))
            if natural.height > remaining { full = true }
            frames.append(CGRect(x: 0, y: y, width: width, height: size.height))
            widest = max(widest, size.width)
            y += size.height
        }
        return Arrangement(frames: frames, height: y, width: widest)
    }
}

/// The slim dotted rule that stands for a blank line.
private struct ParagraphGap: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: CardLayout.paragraphGap / 2))
            path.addLine(to: CGPoint(x: 400, y: CardLayout.paragraphGap / 2))
        }
        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3]))
        .foregroundStyle(AdaptiveContrast.quiet(contrast).opacity(0.5))
        .clipped()
        .accessibilityHidden(true)
    }
}
