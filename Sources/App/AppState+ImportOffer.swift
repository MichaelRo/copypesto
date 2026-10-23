// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

extension AppState {
    /// Asks the detector which clipboard managers are installed, by bundle identifier only. Settings, Data calls it
    /// when
    /// the pane appears; the launch offer asks through `refreshImportOffer`.
    func refreshInstalledImportSources() {
        let installed = clipboardAppDetector.installed()
        if installed != installedImportSources { installedImportSources = installed }
    }

    /// Looks for installed clipboard managers to offer to import from. It runs at launch and when setup finishes, and
    /// stops offering once the person has answered (`Setting.importOffered`).
    func refreshImportOffer() {
        refreshInstalledImportSources()
        importOffer = ImportOfferPolicy.sources(
            installed: clipboardAppDetector.installed(),
            alreadyOffered: AppDefaults.store.value(for: Setting.importOffered),
            hasOnboarded: AppDefaults.store.value(for: Setting.hasOnboarded)
        )
    }

    /// Either answer ends the offer for good. Accepting opens Settings, Data: with one app the import starts there with
    /// its sheet, with several the Found on this Mac card is shown and each import is started from its own row, so each
    /// keeps its own consent (ADR 0011).
    func answerImportOffer(accepted: Bool) {
        let offered = importOffer
        AppDefaults.store.set(true, for: Setting.importOffered)
        importOffer = []
        guard accepted, !offered.isEmpty else { return }
        if offered.count == 1 {
            pendingImportSource = offered.first
        } else {
            pendingSettingsRow = SettingsIndex.foundOnThisMacTitle
        }
        pendingSettingsSection = SettingsSection.data.rawValue
        openSettingsFromOverlay?()
    }
}
