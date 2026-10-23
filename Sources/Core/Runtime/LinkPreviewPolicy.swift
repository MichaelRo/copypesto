// SPDX-License-Identifier: MIT
import Foundation

/// Loading a link's preview contacts the linked page, so it is off until the person turns it on (H-03).
public enum LinkPreviewPolicy {
    public static let defaultsKey = "linkPreviewsEnabled"

    /// Only a normal launch contacts the network: a test host or UI-test launch shows no previews, whatever is stored.
    public static func isEnabled(in store: UserDefaults = AppDefaults.store, mode: LaunchMode = .current) -> Bool {
        guard mode == .normal else { return false }
        return store.bool(forKey: defaultsKey)
    }

    /// The GIF behind a browser's Copy Image follows the same switch and the same address checks as a preview, and a
    /// locked history causes no request at all (a copy made while locked keeps its still).
    public static func mayFetchGIF(isEnabled: Bool, isEligible: Bool, isHistoryLocked: Bool) -> Bool {
        isEnabled && isEligible && !isHistoryLocked
    }
}
