// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
@testable import PestoMobile

@Suite("A card's GIF frames are held only while the card is on screen, decoded after it settles, a few at a time")
@MainActor
struct GIFPlaybackTests {
    private actor Tally {
        private(set) var running = 0
        private(set) var peak = 0
        private(set) var finished = 0

        func begin() {
            running += 1
            peak = max(peak, running)
        }

        func end() {
            running -= 1
            finished += 1
        }
    }

    @MainActor
    private final class Counter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    private func animation() -> GIFFrames.Animation {
        GIFFrames.Animation(frames: [UIImage(), UIImage()], duration: 1)
    }

    private func animatedState() -> CardMediaState {
        CardMediaState(picture: .init(image: UIImage(), isAnimated: true))
    }

    @Test("no more than the limit decode at once, and every one still runs")
    func whenManyDecode_thenOnlyTheLimitRunsTogether() async {
        let gate = GIFDecodeGate(limit: 2)
        let tally = Tally()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    _ = await gate.run { () async -> Int? in
                        await tally.begin()
                        try? await Task.sleep(for: .milliseconds(20))
                        await tally.end()
                        return 1
                    }
                }
            }
        }

        #expect(await tally.peak == 2)
        #expect(await tally.finished == 8)
    }

    @Test("a card that leaves before it has settled decodes nothing")
    func whenCancelledWhileSettling_thenNothingIsDecoded() async {
        let state = animatedState()
        let decodes = Counter()
        let task = Task {
            await state.animate(settleDelay: .seconds(5)) {
                decodes.increment()
                return animation()
            }
        }
        task.cancel()
        await task.value

        #expect(decodes.count == 0)
        #expect(state.picture?.animation == nil)
    }

    @Test("a card that stays gets its frames, and leaving drops them and keeps the still")
    func whenSettledThenLeft_thenTheStillStays() async {
        let state = animatedState()

        await state.animate(settleDelay: .milliseconds(1)) { animation() }
        #expect(state.picture?.animation != nil)

        state.dropAnimation()
        #expect(state.picture?.animation == nil)
        #expect(state.picture?.isAnimated == true)
    }

    @Test("a still picture never decodes frames, and frames already held are not decoded again")
    func whenNotAnimatedOrAlreadyPlaying_thenNothingIsDecoded() async {
        let still = CardMediaState(picture: .init(image: UIImage(), isAnimated: false))
        let decodes = Counter()
        await still.animate(settleDelay: .milliseconds(1)) {
            decodes.increment()
            return animation()
        }
        #expect(decodes.count == 0)

        let playing = animatedState()
        await playing.animate(settleDelay: .milliseconds(1)) { animation() }
        await playing.animate(settleDelay: .milliseconds(1)) {
            decodes.increment()
            return animation()
        }
        #expect(decodes.count == 0)
    }
}
