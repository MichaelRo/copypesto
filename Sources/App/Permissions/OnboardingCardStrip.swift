// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Real shelf cards over sample clips on the ready screen, of several kinds, so it shows what Pesto looks like (and
/// that the shelf holds more) without a screenshot that can drift from the shelf. The row drifts slowly along itself
/// until the pointer rests on it or the person scrolls it with a trackpad or wheel, which keeps it where they left it.
/// The cards cannot be tapped and are hidden from VoiceOver.
struct OnboardingCardStrip: View {
    @AppStorage(Setting.cardSize) private var cardSizeRaw: String
    @AppStorage(Setting.cardWidth) private var cardWidth: Int
    @State private var position = ScrollPosition(edge: .leading)
    @State private var offset: CGFloat = 0
    @State private var farthest: CGFloat = 0
    @State private var isHovered = false
    @State private var motion = CardStripDrift(offset: 0)
    @State private var wasScrolledByHand = false
    @State private var offsetWhenHandScrollBegan: CGFloat = 0
    @State private var resumeDriftTask: Task<Void, Never>?

    static let height: CGFloat = 150
    /// How long the row rests after the person stops scrolling it: long enough not to fight a second flick, short
    /// enough
    /// that it does not look stuck.
    static let resumeDelay = 1.2

    private var isDrifting: Bool {
        !Motion.reduceMotion && !isHovered && !wasScrolledByHand
    }

    var body: some View {
        let size = CardSize.dimensions(sizeRaw: cardSizeRaw, customWidth: cardWidth)
        ScrollView(.horizontal, showsIndicators: false) {
            SampleCardStrip(kinds: SampleCardStrip.Kind.allCases, scale: Self.height / size.height)
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .scrollPosition($position)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentSize.width - $0.containerSize.width) } action: {
            farthest = $1
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { offset = $1 }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting {
                if !wasScrolledByHand { offsetWhenHandScrollBegan = offset }
                resumeDriftTask?.cancel()
                resumeDriftTask = nil
                wasScrolledByHand = true
            } else if phase == .idle, wasScrolledByHand {
                withTransaction(Transaction(animation: nil)) { position.scrollTo(x: offset) }
                if abs(offset - offsetWhenHandScrollBegan) >
                    2 { motion.turn(forward: offset > offsetWhenHandScrollBegan) }
                resumeDriftTask?.cancel()
                resumeDriftTask = Task {
                    try? await Task.sleep(for: .seconds(Self.resumeDelay))
                    guard !Task.isCancelled else { return }
                    wasScrolledByHand = false
                }
            }
        }
        .onHover { isHovered = $0 }
        .task(id: isDrifting) { await drift() }
        .mask(LinearGradient(
            stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.9), .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        ))
    }

    private func drift() async {
        guard isDrifting else {
            // A scroll still running when the pointer arrives is stopped where it is.
            withTransaction(Transaction(animation: nil)) { position.scrollTo(x: offset) }
            motion.pause()
            return
        }
        // Wait for the initial geometry pass if `farthest` has not been measured yet.
        for _ in 0..<20 where farthest <= 0 && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard !Task.isCancelled, farthest > 0 else { return }
        motion.place(at: offset, farthest: farthest)
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = clock.now
            let elapsed = last.duration(to: now)
            last = now
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            motion.advance(by: min(seconds, 0.1), farthest: farthest)
            withTransaction(Transaction(animation: nil)) { position.scrollTo(x: motion.offset) }
            offset = motion.offset
        }
    }
}
