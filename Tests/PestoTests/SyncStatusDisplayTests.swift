// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import Testing
@testable import Pesto

@Suite("Mac sync status display")
struct SyncStatusDisplayTests {
    @Test("iCloud storage-full names iCloud Drive and explains clips wait until space is free")
    func whenICloudStorageIsFull_thenDisplaysICloudMessage() {
        let status = SyncStatus.storageFull(isICloud: true)

        #expect(status.title == "iCloud Drive is full")
        #expect(status.detail.contains("wait on this Mac until space is free"))
        #expect(!status.title.localizedCaseInsensitiveContains("up to date"))
        #expect(status.dotColor == .statusBad)
        #expect(status.chipText == String(localized: "Sync: Needs You"))
    }

    @Test("local sync folder full names the sync folder and explains clips wait until space is free")
    func whenSyncFolderStorageIsFull_thenDisplaysFolderMessage() {
        let status = SyncStatus.storageFull(isICloud: false)

        #expect(status.title == "Sync folder is full")
        #expect(status.detail.contains("wait on this Mac until space is free"))
        #expect(!status.title.localizedCaseInsensitiveContains("up to date"))
        #expect(status.dotColor == .statusBad)
        #expect(status.chipText == String(localized: "Sync: Needs You"))
    }
}
