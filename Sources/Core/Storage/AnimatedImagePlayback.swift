// SPDX-License-Identifier: MIT
import Foundation

public enum AnimatedImagePlayback {
    /// Apple's guidance: pause animated images when the user turns off Auto-Play Animated Images, and honour Reduce
    /// Motion. Either one stops autoplay in the shelf; hovering or focusing a card is an explicit request to play it.
    public static func autoPlayAllowed(systemAnimatedImages: Bool, reduceMotion: Bool) -> Bool {
        systemAnimatedImages && !reduceMotion
    }

    public static func shouldAnimate(autoPlayAllowed: Bool, isActive: Bool) -> Bool {
        autoPlayAllowed || isActive
    }

    /// Normalizes a GIF frame delay (browsers and ImageIO treat delays under 20 ms as 100 ms).
    public static func normalizedDuration(_ rawDelay: TimeInterval) -> TimeInterval {
        rawDelay < 0.02 ? 0.10 : rawDelay
    }

    /// Resolves which frame index should be shown at a monotonic timestamp `uptime`, so the shelf card and the hover
    /// card play the same GIF in lockstep.
    public static func frameIndex(at uptime: TimeInterval, durations: [TimeInterval]) -> Int {
        guard !durations.isEmpty else { return 0 }
        let normalized = durations.map(normalizedDuration)
        let total = normalized.reduce(0, +)
        guard total > 0 else { return 0 }
        var phase = uptime.truncatingRemainder(dividingBy: total)
        if phase < 0 { phase += total }
        var accumulated: TimeInterval = 0
        for (index, duration) in normalized.enumerated() {
            accumulated += duration
            if phase < accumulated { return index }
        }
        return normalized.count - 1
    }
}
