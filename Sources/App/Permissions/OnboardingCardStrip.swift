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
    @State private var wasScrolledByHand = false
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
                resumeDriftTask?.cancel()
                resumeDriftTask = nil
                wasScrolledByHand = true
            } else if phase == .idle, wasScrolledByHand {
                withTransaction(Transaction(animation: nil)) { position.scrollTo(x: offset) }
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
            return
        }
        // Wait for the initial geometry pass if `farthest` has not been measured yet.
        for _ in 0..<20 where farthest <= 0 && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard !Task.isCancelled, farthest > 0 else { return }
        // Step smoothly so `offset` always reflects the real scroll position when the pointer enters or leaves.
        let pointsPerTick: CGFloat = 1.65 // ~100 pt/s at 60 Hz
        var forward = offset < max(farthest - 30, 1)
        var current = offset

        while !Task.isCancelled {
            current = forward
                ? min(farthest, current + pointsPerTick)
                : max(0, current - pointsPerTick)
            withTransaction(Transaction(animation: nil)) {
                position.scrollTo(x: current)
            }
            offset = current
            if (forward && current >= farthest - 0.5) || (!forward && current <= 0.5) {
                forward.toggle()
                try? await Task.sleep(for: .milliseconds(350))
            } else {
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}
