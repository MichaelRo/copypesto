// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Animated image playback")
struct AnimatedImagePlaybackTests {
    @Test("when the user allows auto-play, every card plays")
    func whenAutoPlayAllowed_thenPlaysWithoutInteraction() {
        #expect(AnimatedImagePlayback.shouldAnimate(autoPlayAllowed: true, isActive: false))
        #expect(AnimatedImagePlayback.shouldAnimate(autoPlayAllowed: true, isActive: true))
    }

    @Test("when auto-play is off (the system setting or Reduce Motion), a card plays only while hovered or focused")
    func whenAutoPlayOff_thenPlaysOnlyWhenActive() {
        #expect(!AnimatedImagePlayback.shouldAnimate(autoPlayAllowed: false, isActive: false))
        #expect(AnimatedImagePlayback.shouldAnimate(autoPlayAllowed: false, isActive: true))
    }

    @Test("auto-play needs the system setting on and Reduce Motion off")
    func whenSettings_thenAutoPlayAllowed() {
        #expect(AnimatedImagePlayback.autoPlayAllowed(systemAnimatedImages: true, reduceMotion: false))
        #expect(!AnimatedImagePlayback.autoPlayAllowed(systemAnimatedImages: false, reduceMotion: false))
        #expect(!AnimatedImagePlayback.autoPlayAllowed(systemAnimatedImages: true, reduceMotion: true))
        #expect(!AnimatedImagePlayback.autoPlayAllowed(systemAnimatedImages: false, reduceMotion: true))
    }

    @Test("two views reading the same monotonic clock resolve the same GIF frame index")
    func whenSharedClock_thenFrameIndexMatchesElapsedPhase() {
        let durations = [0.10, 0.20, 0.10]
        #expect(AnimatedImagePlayback.frameIndex(at: 0.05, durations: durations) == 0)
        #expect(AnimatedImagePlayback.frameIndex(at: 0.15, durations: durations) == 1)
        #expect(AnimatedImagePlayback.frameIndex(at: 0.35, durations: durations) == 2)
        #expect(AnimatedImagePlayback.frameIndex(at: 0.45, durations: durations) == 0)
    }
}
