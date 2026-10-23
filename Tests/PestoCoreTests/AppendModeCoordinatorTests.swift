// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1000)

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

@Suite("AppendModeCoordinator")
struct AppendModeCoordinatorTests {
    private let clock = ManualClock()
    private let coordinator: AppendModeCoordinator

    init() {
        let clock = clock
        coordinator = AppendModeCoordinator(window: 0.5, appendLifetime: 1.0, now: { clock.now })
    }

    @Test("a single copy does not start append mode")
    func whenOneCopy_thenNoAppend() async {
        let isDouble = await coordinator.markCopy()

        #expect(!isDouble)
        #expect(await !coordinator.shouldAppend())
    }

    @Test("a second copy inside the window starts append mode")
    func whenTwoCopiesInsideTheWindow_thenAppend() async {
        await coordinator.markCopy()
        clock.advance(by: 0.3)

        #expect(await coordinator.markCopy())
        #expect(await coordinator.shouldAppend())
    }

    @Test("a second copy outside the window is a new first copy")
    func whenTwoCopiesOutsideTheWindow_thenNoAppend() async {
        await coordinator.markCopy()
        clock.advance(by: 0.6)

        #expect(await !coordinator.markCopy())
        #expect(await !coordinator.shouldAppend())
    }

    @Test("append mode expires a second after it started")
    func whenTheLifetimePasses_thenAppendEnds() async {
        await coordinator.markCopy()
        clock.advance(by: 0.2)
        await coordinator.markCopy()
        clock.advance(by: 0.9)
        #expect(await coordinator.shouldAppend())

        clock.advance(by: 0.2)

        #expect(await !coordinator.shouldAppend())
    }

    @Test("reset ends append mode, so one double copy appends once")
    func whenReset_thenAppendEnds() async {
        await coordinator.markCopy()
        await coordinator.markCopy()

        await coordinator.reset()

        #expect(await !coordinator.shouldAppend())
    }

    @Test("a triple press keeps the chain: each press is judged against the one before it")
    func whenThreePresses_thenEachJudgedAgainstThePrevious() async {
        await coordinator.markCopy()
        clock.advance(by: 0.4)
        #expect(await coordinator.markCopy())
        await coordinator.reset()
        clock.advance(by: 0.4)

        #expect(await coordinator.markCopy())
    }
}
