// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What leaves this Mac, in words")
struct PrivacyNetworkFactsTests {
    private let drive = URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Pesto")
    private let other = URL(fileURLWithPath: "/Volumes/Backup/Pesto")

    @Test("a backup that is off says Off")
    func off() {
        #expect(PrivacyNetworkFacts.backup(enabled: false, automatic: true, folder: drive) == "Off")
    }

    @Test("a backup in iCloud Drive says that macOS uploads it")
    func iCloudDrive() {
        let text = PrivacyNetworkFacts.backup(enabled: true, automatic: true, folder: drive)
        #expect(text.contains("iCloud Drive"))
        #expect(text.contains("macOS uploads"))
    }

    @Test("a backup in another folder does not claim anything about uploading")
    func otherFolder() {
        let text = PrivacyNetworkFacts.backup(enabled: true, automatic: false, folder: other)
        #expect(text.contains("a folder you chose"))
        #expect(!text.contains("iCloud"))
    }

    @Test("the mode is stated: kept up to date, or only on request")
    func mode() {
        #expect(PrivacyNetworkFacts.backup(enabled: true, automatic: true, folder: other).contains("automatic"))
        #expect(PrivacyNetworkFacts.backup(enabled: true, automatic: false, folder: other).contains("Back Up Now"))
    }

    @Test("the clips row says what Pesto does, not what Apple's cloud might do")
    func clips() {
        #expect(PrivacyNetworkFacts.clips == "Not uploaded by Pesto")
    }

    @Test("the update row names where an accepted update is downloaded from")
    func updates() {
        #expect(PrivacyNetworkFacts.updates.contains("GitHub"))
    }
}
