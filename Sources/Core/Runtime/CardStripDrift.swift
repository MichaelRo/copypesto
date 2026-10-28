// SPDX-License-Identifier: MIT
import CoreGraphics

/// The slow back-and-forth of the sample cards on the ready screen, as pure math so its pace and direction are tested:
/// it eases in whenever it starts, slows toward each end, waits there, and keeps its direction across a pause.
public struct CardStripDrift: Equatable, Sendable {
    public static let cruiseSpeed: CGFloat = 36
    public static let rampSeconds = 1.0
    public static let easeDistance: CGFloat = 90
    public static let endPauseSeconds = 0.8
    private static let slowestShare: CGFloat = 0.2

    public private(set) var offset: CGFloat
    public private(set) var movesForward = true
    private var secondsMoving = 0.0
    private var pauseLeft = 0.0

    public init(offset: CGFloat) {
        self.offset = offset
    }

    /// The pointer arrived or the person took over: the next start eases in again.
    public mutating func pause() {
        secondsMoving = 0
    }

    public mutating func place(at newOffset: CGFloat, farthest: CGFloat = .greatestFiniteMagnitude) {
        offset = min(max(0, newOffset), max(0, farthest))
    }

    public mutating func advance(by seconds: Double, farthest: CGFloat) {
        guard farthest > 0, seconds > 0 else { return }
        offset = min(offset, farthest)
        if pauseLeft > 0 {
            pauseLeft -= seconds
            return
        }
        secondsMoving += seconds
        let ramp = CGFloat(min(1, secondsMoving / Self.rampSeconds))
        let eased = ramp * ramp * (3 - 2 * ramp)
        let remaining = movesForward ? farthest - offset : offset
        let nearEnd = min(1, max(Self.slowestShare, remaining / Self.easeDistance))
        let step = Self.cruiseSpeed * eased * nearEnd * CGFloat(seconds)
        offset += movesForward ? step : -step
        offset = min(max(0, offset), farthest)

        if (movesForward && offset >= farthest - 0.5) || (!movesForward && offset <= 0.5) {
            offset = movesForward ? farthest : 0
            movesForward.toggle()
            secondsMoving = 0
            pauseLeft = Self.endPauseSeconds
        }
    }
}
