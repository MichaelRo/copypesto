// SPDX-License-Identifier: MIT
import Foundation

enum GIFPlayback {
    static let settleDelay: Duration = .milliseconds(250)
    static let maxConcurrentDecodes = 2
}

/// Lets only a few GIFs decode at once: a fast scroll creates dozens of cards, and each decode holds up to 12 MB.
actor GIFDecodeGate {
    static let shared = GIFDecodeGate(limit: GIFPlayback.maxConcurrentDecodes)

    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func run<Result: Sendable>(_ work: @Sendable () async -> Result?) async -> Result? {
        await acquire()
        defer { release() }
        guard !Task.isCancelled else { return nil }
        return await work()
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
