// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
@testable import PestoMobile

@MainActor
private final class FakeSystem {
    var begun: [String] = []
    var ended: [UIBackgroundTaskIdentifier] = []
    var expire: (@MainActor () -> Void)?

    var work: BackgroundWork {
        BackgroundWork(
            begin: { [self] name, expired in
                begun.append(name)
                expire = expired
                return UIBackgroundTaskIdentifier(rawValue: begun.count)
            },
            end: { [self] in ended.append($0) }
        )
    }
}

@Suite("Time asked of iOS for a write as the app leaves the front is always given back once")
@MainActor
struct BackgroundWorkTests {
    @Test("the work finishing ends the assertion it began, once")
    func whenTheWorkFinishes_thenTheAssertionEndsOnce() {
        let system = FakeSystem()
        let hold = system.work.hold("Widget snapshot")
        #expect(system.begun == ["Widget snapshot"])
        #expect(system.ended.isEmpty)

        hold.finish()
        hold.finish()

        #expect(system.ended == [UIBackgroundTaskIdentifier(rawValue: 1)])
    }

    @Test("iOS ending the time first ends it, and the work finishing later ends nothing more")
    func whenTheTimeRunsOutFirst_thenTheAssertionEndsOnce() {
        let system = FakeSystem()
        let hold = system.work.hold("Widget snapshot")

        system.expire?()
        hold.finish()

        #expect(system.ended == [UIBackgroundTaskIdentifier(rawValue: 1)])
    }

    @Test("leaving the front holds the time until the widget's snapshot is written")
    func whenTheAppLeavesTheFront_thenTheWidgetWriteIsHeld() async throws {
        let library = try await MobileTestLibrary()
        let system = FakeSystem()
        library.state.backgroundWork = system.work

        library.state.didLeaveForeground()
        #expect(system.begun == ["Widget snapshot"])
        for _ in 0..<100 where system.ended.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(system.ended.count == 1)
    }
}
