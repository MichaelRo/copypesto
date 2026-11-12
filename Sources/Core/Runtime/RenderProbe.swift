// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// Counts how many times a view's body ran, per name, so an interaction can be judged by the work it caused and not
/// only by how long it took: one arrow press that re-runs every card shows up here on any Mac, while a hitch only shows
/// on a slow one. Counting happens only in a perf-timeline run (`PerfTimeline.isRecording`), so it costs a branch.
public final class RenderCounter: Sendable {
    private let counts = Mutex<[String: Int]>([:])

    public init() {}

    public func hit(_ name: String) {
        add(name, 1)
    }

    public func add(_ name: String, _ amount: Int) {
        counts.withLock { $0[name, default: 0] += amount }
    }

    /// The counts since the last call, and a fresh start.
    public func drain() -> [String: Int] {
        counts.withLock { value in
            defer { value = [:] }
            return value
        }
    }

    public static func summary(_ counts: [String: Int]) -> String {
        counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }
}

public enum RenderProbe {
    public static let shared = RenderCounter()

    public static func reset() {
        _ = shared.drain()
    }

    /// Runs `work` and adds the microseconds it took to `name`: how long building a view's body took, apart from the
    /// layout and drawing SwiftUI does afterwards. Costs one branch outside a perf-timeline run.
    public static func timed<Result>(_ name: StaticString, _ work: () -> Result) -> Result {
        guard PerfTimeline.isRecording else { return work() }
        let started = PerfTimeline.now()
        defer { shared.add("\(name)", Int((PerfTimeline.now() - started) / 1000)) }
        return work()
    }

    public static func hit(_ name: StaticString) {
        guard PerfTimeline.isRecording else { return }
        shared.hit("\(name)")
    }

    /// Writes what ran since the last report as one timeline event named for the interaction that caused it.
    public static func report(after interaction: String) {
        guard PerfTimeline.isRecording else { return }
        PerfSignposts.shelf.event("renders", "\(interaction) \(RenderCounter.summary(shared.drain()))")
    }
}
