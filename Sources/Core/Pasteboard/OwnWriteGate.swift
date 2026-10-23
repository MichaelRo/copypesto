// SPDX-License-Identifier: MIT
import Synchronization

public final class OwnWriteGate: Sendable {
    private struct State {
        var openWrites = 0
        var ignoredUpTo = 0
    }

    private let state = Mutex(State())

    public init() {}

    public var isWriting: Bool {
        state.withLock { $0.openWrites > 0 }
    }

    public func isOwn(changeCount: Int) -> Bool {
        state.withLock { $0.openWrites > 0 || changeCount <= $0.ignoredUpTo }
    }

    @discardableResult
    public func write<Board: ChangeCounting, Result>(
        to pasteboard: Board,
        _ body: (Board) throws -> Result
    ) rethrows
    -> Result {
        state.withLock { $0.openWrites += 1 }
        defer {
            state.withLock {
                $0.openWrites -= 1
                $0.ignoredUpTo = max($0.ignoredUpTo, pasteboard.changeCount)
            }
        }
        return try body(pasteboard)
    }
}
