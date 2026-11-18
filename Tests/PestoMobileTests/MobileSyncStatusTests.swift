// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The Sync screen's status line never claims success it has not seen")
struct MobileSyncStatusTests {
    private static let notYetExchanged: [SyncStatus] = [
        .off, .paused, .receiving(done: 1, total: 4), .waitingForFolder, .folderMissing,
        .nothingNew(since: .now), .needsKey, .refused("A file from another device is damaged.")
    ]
    private static let successWords = ["up to date", "connected", "synced", "in sync", "all set"]

    private func readsAsSuccess(_ status: MobileSyncStatus) -> Bool {
        let text = (status.title + " " + status.detail).lowercased()
        return status.tone == .good || Self.successWords.contains { text.contains($0) }
    }

    @Test("every state before a completed exchange reads as something other than success", arguments: notYetExchanged)
    func whenNoExchangeHasCompleted_thenTheStatusIsNotSuccess(_ status: SyncStatus) {
        let line = MobileSyncStatus(folderProblem: nil, isEnabled: true, status: status, device: .iPhone)
        #expect(!readsAsSuccess(line), "\(status) read as \(line)")
    }

    @Test("only a completed exchange reads as up to date")
    func whenAnExchangeCompleted_thenTheStatusIsUpToDate() {
        let line = MobileSyncStatus(folderProblem: nil, isEnabled: true, status: .upToDate(.now), device: .iPhone)
        #expect(line.tone == .good)
        #expect(line.title == String(localized: "Up to date"))
    }

    @Test("a sync that is enabled but has no status yet reads as checking")
    func whenThereIsNoStatusYet_thenItReadsAsChecking() {
        let line = MobileSyncStatus(folderProblem: nil, isEnabled: true, status: nil, device: .iPad)
        #expect(!readsAsSuccess(line))
        #expect(line.title == String(localized: "Checking the folder"))
    }

    @Test(
        "a folder that cannot be used is a repair, even when the last exchange was a success",
        arguments: [SyncFolderProblem.stale, .unresolvable, .unreachable]
    )
    func whenTheFolderNeedsRepair_thenTheStatusAsksForIt(_ problem: SyncFolderProblem) {
        let line = MobileSyncStatus(folderProblem: problem, isEnabled: true, status: .upToDate(.now), device: .iPhone)
        #expect(line.needsFolder)
        #expect(line.tone == .problem)
        #expect(!readsAsSuccess(line))
        #expect(line.title == String(localized: "Choose the folder again"))
    }

    @Test("a folder that went missing while sync ran asks for the folder too")
    func whenTheFolderIsMissing_thenTheStatusAsksForIt() {
        let line = MobileSyncStatus(folderProblem: nil, isEnabled: true, status: .folderMissing, device: .iPhone)
        #expect(line.needsFolder)
    }

    @Test("sync that is off says so, in an iPhone's words")
    func whenSyncIsOff_thenItSaysSo() {
        let line = MobileSyncStatus(folderProblem: nil, isEnabled: false, status: .upToDate(.now), device: .iPhone)
        #expect(!readsAsSuccess(line))
        #expect(line.detail == SyncCopy.offDetail(.iPhone))
        #expect(!line.detail.contains("Mac"))
    }
}
