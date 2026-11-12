// SPDX-License-Identifier: MIT
import Foundation

/// Decides whether a collection switch draws real cards or light placeholders. A Mac on which a full switch commits
/// slowly,
/// asked for another within a moment, draws the second with placeholders (a flat card is about a quarter of the work)
/// and
/// puts the real cards back once the person stops. A switch after a pause, and every switch on a Mac that commits them
/// quickly, is drawn in full: nobody who switches once sees a placeholder.
public struct SwitchQualityPolicy: Sendable, Equatable {
    public enum Quality: Sendable, Equatable {
        case full
        case light
    }

    public var slowMillis = 40.0
    public var quickWindow = Duration.milliseconds(450)
    /// How long the shelf is still before the real cards replace the placeholders.
    public var settle = Duration.milliseconds(150)

    /// Switches in a row, each within `quickWindow` of the one before, that must have happened before one is drawn
    /// light: a
    /// second switch is a person choosing a collection, a third is a person going through them.
    public var quickRunToEngage = 2

    public private(set) var fullCommitMillis: Double?
    private var lastSwitch: ContinuousClock.Instant?
    private var quickRun = 0

    public init() {}

    public mutating func quality(at now: ContinuousClock.Instant) -> Quality {
        defer { lastSwitch = now }
        guard let last = lastSwitch else { return .full }
        quickRun = now - last < quickWindow ? quickRun + 1 : 0
        guard let cost = fullCommitMillis else { return .full }
        return cost > slowMillis && quickRun >= quickRunToEngage ? .light : .full
    }

    /// What a switch took to reach the screen. Only a full one says what a full one costs: a light one is quick by
    /// design.
    public mutating func committed(_ quality: Quality, millis: Double) {
        if quality == .full { fullCommitMillis = millis }
    }
}
