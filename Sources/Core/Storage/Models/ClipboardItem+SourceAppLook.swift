// SPDX-License-Identifier: MIT
import Foundation

public extension ClipboardItem {
    /// The app and sampled color this device knows for the clip. A clip that arrived on another device's clipboard
    /// (`isRemote`) names no app here, as the iOS card shows none for it.
    var sourceAppLook: SourceAppLook {
        isRemote ? .none : SourceAppLook(bundleID: sourceBundleID, colorHex: sourceDominantColorHex)
    }
}
