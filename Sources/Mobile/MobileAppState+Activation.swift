// SPDX-License-Identifier: MIT
import PestoCore

/// What runs when Pesto comes to the front: a cold launch and each return from the background run it once, however
/// many times SwiftUI reports the scene as active.
extension MobileAppState {
    func activate() async {
        HangDiagnostics.measure("boot") { boot() }
        guard !isActivated else { return }
        isActivated = true
        activationCount += 1
        lockDidBecomeActive()
        reconcileKeyboardSize()
        await Task.yield()
        await syncDidBecomeActiveAsync()
        inboxDidBecomeActive()
        await clipboardDidBecomeActive()
        await refreshWidgetPresence()
        await pruneHistory()
        startSimilarityWork()
    }
}
