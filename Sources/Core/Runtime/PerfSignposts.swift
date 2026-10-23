// SPDX-License-Identifier: MIT
import Foundation
import os
import Synchronization

/// Signpost intervals on the copy, paste and shelf paths. They cost nothing while Instruments is not recording.
/// A latency-bench launch (`PESTO_UITEST_REAL_PASTE`) also writes each interval to `perf-timeline.tsv` in the working
/// folder on the system uptime clock, so `scripts/bench-latency.sh` can line the stages up with the key press and the
/// moment the target app received the clip without a profiler.
public enum PerfSignposts {
    public static let copy = PerfChannel(category: "Copy")
    public static let paste = PerfChannel(category: "Paste")
    public static let shelf = PerfChannel(category: "Shelf")
}

public struct PerfChannel: Sendable {
    fileprivate let signposter: OSSignposter
    fileprivate let category: String

    init(category: String) {
        signposter = OSSignposter(subsystem: AppIdentity.logSubsystem, category: category)
        self.category = category
    }

    public func begin(_ name: StaticString) -> PerfInterval {
        PerfInterval(
            channel: self, name: name,
            state: signposter.beginInterval(name, id: signposter.makeSignpostID()),
            startNanos: PerfTimeline.isRecording ? PerfTimeline.now() : 0
        )
    }

    public func event(_ name: StaticString, _ detail: String) {
        signposter.emitEvent(name, "\(detail, privacy: .private)")
        if PerfTimeline.isRecording {
            let now = PerfTimeline.now()
            PerfTimeline.record(channel: category, name: "\(name)(\(detail))", start: now, end: now)
        }
    }
}

public struct PerfInterval: Sendable {
    fileprivate let channel: PerfChannel
    fileprivate let name: StaticString
    fileprivate let state: OSSignpostIntervalState
    fileprivate let startNanos: UInt64

    public func end() {
        channel.signposter.endInterval(name, state)
        if PerfTimeline.isRecording {
            PerfTimeline.record(channel: channel.category, name: "\(name)", start: startNanos, end: PerfTimeline.now())
        }
    }

    /// Ends once the main run loop has finished the pass it is in, after Core Animation's commit (observer order
    /// 2,000,000): the nearest thing to "the first frame was submitted" that needs no private API.
    @MainActor
    public func endAfterNextCommit() {
        let interval = self
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, false, 2_100_000
        ) { _, _ in interval.end() }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}

/// Back-to-back stages of one operation: starting the next ends the previous one, and `finish()` ends the last, so an
/// early return leaves no interval open.
public final class PerfStages: Sendable {
    private let channel: PerfChannel
    private let current = Mutex<PerfInterval?>(nil)

    public init(_ channel: PerfChannel, first: StaticString) {
        self.channel = channel
        current.withLock { $0 = channel.begin(first) }
    }

    public func next(_ name: StaticString) {
        let previous = current.withLock { slot in
            defer { slot = channel.begin(name) }
            return slot
        }
        previous?.end()
    }

    public func finish() {
        let previous = current.withLock { slot in
            defer { slot = nil }
            return slot
        }
        previous?.end()
    }
}

enum PerfTimeline {
    static let isRecording = isEnabled(for: RuntimeConfiguration.current)

    static func isEnabled(for configuration: RuntimeConfiguration) -> Bool {
        configuration.mode == .uiTest && (configuration.usesRealPasteboard || configuration.recordsPerfTimeline)
    }

    static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    static func line(channel: String, name: String, start: UInt64, end: UInt64) -> String {
        "\(channel)\t\(name)\t\(start)\t\(end)\n"
    }

    private static let file = Mutex<FileHandle?>(nil)

    static func record(channel: String, name: String, start: UInt64, end: UInt64) {
        let data = Data(line(channel: channel, name: name, start: start, end: end).utf8)
        file.withLock { handle in
            if handle == nil {
                let url = AppPaths.supportDirectory.appendingPathComponent("perf-timeline.tsv")
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                _ = try? handle?.seekToEnd()
            }
            try? handle?.write(contentsOf: data)
        }
    }
}
