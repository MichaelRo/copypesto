// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import SwiftUI
import Testing
@testable import Pesto

@Suite("RestoreSheet holds back shorter retention settings and applies them on Apply These Too")
@MainActor
struct BackupRestoreRetentionViewTests {
    @Test("restoring a backup with shorter retention surfaces held-back items and applies them on approval")
    func whenBackupHasShorterRetention_thenHeldBackIsOfferedAndApplyTheseTooCommitsIt() throws {
        let defaults = ThrowawayDefaults.make()
        defaults.set(90, forKey: Setting.retentionDays.name)
        defaults.set(5000, forKey: Setting.retentionMaxItems.name)
        defer {
            defaults.removeObject(forKey: Setting.retentionDays.name)
            defaults.removeObject(forKey: Setting.retentionMaxItems.name)
        }

        let payload = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "settings": [
                Setting.retentionDays.name: 7,
                Setting.retentionMaxItems.name: 500,
                Setting.appTheme.name: "parmesan"
            ]
        ])

        let outcome = try #require(RestoreSheet.restoreSettings(from: payload, into: defaults))
        #expect(outcome.heldBack.count == 2)
        #expect(Set(outcome.heldBack.map(\.key)) == [Setting.retentionDays.name, Setting.retentionMaxItems.name])
        #expect(defaults.string(forKey: Setting.appTheme.name) == "parmesan", "safe settings apply at once")
        #expect(defaults.integer(forKey: Setting.retentionDays.name) == 90, "shorter retention waits for approval")
        #expect(defaults.integer(forKey: Setting.retentionMaxItems.name) == 5000)

        let approved = try #require(RestoreSheet.applyHeldBackSettings(outcome, into: defaults))
        #expect(approved.heldBack.isEmpty)
        #expect(approved.note == "Settings restored.")
        #expect(defaults.integer(forKey: Setting.retentionDays.name) == 7)
        #expect(defaults.integer(forKey: Setting.retentionMaxItems.name) == 500)

        var summary = BackupRestoreSummary()
        summary.restored = 10
        summary.collections = 1
        let heldBackView = RestoreSheet.HeldBackView(summary: summary, settings: outcome)
        let controller = NSHostingController(rootView: heldBackView.defaultAppStorage(defaults))
        let size = controller.sizeThatFits(in: CGSize(width: 400, height: 200))
        #expect(size.height > 30, "heldBackView must lay out with content")
    }
}
