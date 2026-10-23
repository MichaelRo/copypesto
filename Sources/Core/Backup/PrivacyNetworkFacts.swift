// SPDX-License-Identifier: MIT
import Foundation

/// The words the Privacy pane uses for what leaves this Mac, kept apart from the view so they can be tested against
/// the guide.
public enum PrivacyNetworkFacts {
    public static let clips = "Not uploaded by Pesto"
    public static let updates = "Asks Pesto\u{2019}s update server; an accepted update downloads from GitHub"

    public static func backup(enabled: Bool, automatic: Bool, folder: URL?) -> String {
        guard enabled else { return "Off" }
        let inICloudDrive = folder?.path.contains("/Library/Mobile Documents/com~apple~CloudDocs") == true
        let place = inICloudDrive
            ? "An encrypted file in iCloud Drive (macOS uploads it)"
            : "An encrypted file in a folder you chose"
        return place + (automatic ? ", automatic" : ", only when you choose Back Up Now")
    }
}
