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
        let seconds = 18.0
        var forward = offset < max(farthest - 30, 1)
        var isResuming = true

        // It starts from where the row actually is, with no jump: a short ease-in ramps up to the sweep's own speed
        // (about 110 pt/s), and the first sweep runs at that speed before the usual ease-in-out takes over.
        let ramp = forward ? min(48, max(0, farthest - offset)) : -min(48, offset)
        if ramp != 0 {
            withAnimation(Motion.animation(.easeIn(duration: 0.9))) { position.scrollTo(x: offset + ramp) }
            try? await Task.sleep(for: .seconds(0.9))
        }

        while !Task.isCancelled {
            let remaining = forward ? max(0, farthest - offset) : offset
            let fraction = remaining / max(farthest, 1)
            let duration = seconds * max(fraction, 0.08)
            let curve: Animation = isResuming ? .linear(duration: duration) : .easeInOut(duration: duration)
            withAnimation(Motion.animation(curve)) {
                position.scrollTo(x: forward ? farthest : 0)
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { break }

            isResuming = false
            forward.toggle()
            try? await Task.sleep(for: .milliseconds(350))
        }
    }
}
