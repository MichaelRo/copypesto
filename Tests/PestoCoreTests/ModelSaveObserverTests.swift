// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import XCTest
@testable import PestoCore

final class ModelSaveObserverTests: XCTestCase {
    @MainActor
    func test_aSaveOnAnotherThread_neverWaitsForTheMainThread() {
        let observer = ModelSaveObserver.observe {}
        defer { NotificationCenter.default.removeObserver(observer) }
        let posted = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            NotificationCenter.default.post(name: ModelContext.didSave, object: nil)
            posted.signal()
        }

        // The main thread is blocked here, as it is when it waits for the storage actor. A poster that has to wait for
        // it would deadlock: five quick copies froze the app this way.
        let result = posted.wait(timeout: .now() + 3)

        XCTAssertEqual(result, .success, "the notification post waited for the blocked main thread")
    }

    @MainActor
    func test_theHandlerRunsOnTheMainActor() async {
        let ran = expectation(description: "handler ran")
        let observer = ModelSaveObserver.observe {
            XCTAssertTrue(Thread.isMainThread)
            ran.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        DispatchQueue.global().async { NotificationCenter.default.post(name: ModelContext.didSave, object: nil) }

        await fulfillment(of: [ran], timeout: 5)
    }
}
