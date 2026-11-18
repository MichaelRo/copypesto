// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// The one-time AutoFill tip (ADR 0057): offered in the library the first time a clip is pinned or saved as a snippet,
/// never while the History Lock is on, and never again once it has been shown.
extension MobileAppState {
    func clipWasKept(defaults: UserDefaults = AppDefaults.store, isLive: Bool = LaunchMode.current == .normal) {
        guard isLive || defaults.value(for: Setting.uitestShowsAutoFillTip) else { return }
        guard !offersAutoFillTip, !historyLock.isEnabled, !defaults.value(for: Setting.autoFillTipShown),
              !defaults.value(for: Setting.quickInsertEnabled) else { return }
        defaults.set(true, for: Setting.autoFillTipShown)
        offersAutoFillTip = true
    }

    func turnOnAutoFillFromTip(defaults: UserDefaults = AppDefaults.store) async {
        offersAutoFillTip = false
        defaults.set(true, for: Setting.quickInsertEnabled)
        quickInsertSettingChanged()
        await opensAutoFillSettings()
    }

    func dismissAutoFillTip() {
        offersAutoFillTip = false
    }
}
